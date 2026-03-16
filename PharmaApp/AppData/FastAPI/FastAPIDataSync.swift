import Foundation
import CoreData

// MARK: - FastAPIDataSync

/// Synchronizes FastAPI bootstrap data into the Core Data store.
/// This is a one-way sync: API → Core Data. Core Data acts as a read cache.
@MainActor
final class FastAPIDataSync {

    private let context: NSManagedObjectContext
    private let client: FastAPIClient

    init(client: FastAPIClient, persistenceController: PersistenceController) {
        self.client = client
        self.context = persistenceController.container.viewContext
    }

    // MARK: - Full Bootstrap Sync

    /// Fetches all user data from the FastAPI backend and replaces local Core Data.
    func performBootstrapSync() async throws {
        let response: FastAPIBootstrapResponse = try await client.get("/v1/bootstrap")
        try syncBootstrapToCoreData(response)
    }

    // MARK: - Core Data Sync

    private func syncBootstrapToCoreData(_ response: FastAPIBootstrapResponse) throws {
        // Clear all existing operational data
        clearOperationalData()

        // --- Sync people ---
        var personMap: [UUID: Person] = [:]
        for dto in response.people {
            let person = Person(context: context)
            person.id = dto.id
            person.nome = dto.name
            person.cognome = dto.surname
            person.condizione = dto.condition
            person.codice_fiscale = dto.codiceFiscale
            person.is_account = dto.isAccount
            personMap[dto.id] = person
        }

        // --- Sync doctors ---
        var doctorMap: [UUID: Doctor] = [:]
        for dto in response.doctors {
            let doctor = Doctor(context: context)
            doctor.id = dto.id
            doctor.nome = dto.name
            doctor.cognome = dto.surname
            doctor.mail = dto.email
            doctor.telefono = dto.phone
            doctor.indirizzo = dto.address
            doctor.specializzazione = dto.specialization
            if let scheduleJson = dto.scheduleJson,
               let data = try? JSONEncoder().encode(scheduleJson.mapValues { AnyCodable($0.value) }) {
                doctor.orari = String(data: data, encoding: .utf8)
            }
            doctor.segreteria_nome = dto.secretaryName
            doctor.segreteria_mail = dto.secretaryEmail
            doctor.segreteria_telefono = dto.secretaryPhone
            if let secJson = dto.secretaryScheduleJson,
               let data = try? JSONEncoder().encode(secJson.mapValues { AnyCodable($0.value) }) {
                doctor.segreteria_orari = String(data: data, encoding: .utf8)
            }
            doctor.prescription_message_template = dto.prescriptionMessageTemplate
            doctorMap[dto.id] = doctor
        }

        // --- Sync cabinets ---
        var cabinetMap: [UUID: Cabinet] = [:]
        for dto in response.cabinets {
            let cabinet = Cabinet(context: context)
            cabinet.id = dto.id
            cabinet.name = dto.name
            cabinet.is_shared = dto.isShared
            cabinetMap[dto.id] = cabinet
        }

        // --- Sync tracked medicines ---
        var medicineMap: [UUID: Medicine] = [:]
        for dto in response.trackedMedicines {
            let medicine = Medicine(context: context)
            medicine.id = dto.id
            medicine.nome = dto.displayName
            medicine.principio_attivo = dto.principle ?? ""
            medicine.obbligo_ricetta = dto.requiresPrescription
            medicine.catalog_product_key = dto.catalogProductId
            medicine.catalog_country = dto.catalogCountry
            if let labels = dto.labels, let data = try? JSONEncoder().encode(labels) {
                medicine.etichette_json = String(data: data, encoding: .utf8)
            }
            medicine.custom_stock_threshold = Int32(dto.customStockThreshold ?? 0)
            if let cabId = dto.cabinetId, let cabinet = cabinetMap[cabId] {
                medicine.cabinet = cabinet
                medicine.in_cabinet = true
            }
            medicineMap[dto.id] = medicine
        }

        // --- Sync tracked packages ---
        var packageMap: [UUID: Package] = [:]
        for dto in response.trackedPackages {
            let package = Package(context: context)
            package.id = dto.id
            package.denominazione_package = dto.packageLabel
            package.valore = dto.dosageValue.map { Int32($0) } ?? 0
            package.unita = dto.dosageUnit ?? ""
            package.volume = dto.volume ?? ""
            package.numero = Int32(dto.unitsPerPackage)
            package.tipologia = dto.formType ?? ""
            package.catalog_code = dto.catalogCode
            package.catalog_package_key = dto.catalogPackageId
            if let medicine = medicineMap[dto.trackedMedicineId] {
                package.medicine = medicine
            }
            packageMap[dto.id] = package
        }

        // --- Sync medicine entries ---
        for dto in response.medicineEntries {
            guard let medicine = medicineMap[dto.trackedMedicineId],
                  let package = packageMap[dto.trackedPackageId] else { continue }
            let entry = MedicinePackage(context: context)
            entry.id = dto.id
            entry.deadline_month = dto.deadlineMonth.map { Int32($0) } ?? 0
            entry.deadline_year = dto.deadlineYear.map { Int32($0) } ?? 0
            entry.medicine = medicine
            entry.package = package
            if let cabId = dto.cabinetId, let cabinet = cabinetMap[cabId] {
                entry.cabinet = cabinet
            }
        }

        // --- Sync therapies with doses ---
        for dto in response.therapies {
            guard let medicine = medicineMap[dto.trackedMedicineId] else { continue }
            let therapy = Therapy(context: context)
            therapy.id = dto.id
            therapy.condizione = dto.condition
            therapy.medicine = medicine

            // Package (required) — fall back to first package of the medicine
            if let pkgId = dto.trackedPackageId, let pkg = packageMap[pkgId] {
                therapy.package = pkg
            } else if let firstPkg = medicine.packages.first(where: { _ in true }) {
                therapy.package = firstPkg
            }

            therapy.start_date = dto.startDate
            therapy.rrule = buildRruleString(from: dto)
            therapy.importance = dto.importance
            therapy.notification_level = dto.notificationLevel
            therapy.snooze_minutes = Int32(dto.snoozeMinutes)
            therapy.manual_intake_registration = dto.manualIntake
            therapy.notifications_silenced = dto.notificationsSilenced

            // Clinical rules: convert JSON dict to Data
            if let clinicalJson = dto.clinicalRulesJson,
               let data = try? JSONEncoder().encode(clinicalJson.mapValues { AnyCodable($0.value) }) {
                therapy.clinicalRules = data
            }

            // Person (required) — fall back to first person
            if let personId = dto.personId, let person = personMap[personId] {
                therapy.person = person
            } else if let firstPerson = personMap.values.first {
                therapy.person = firstPerson
            }

            if let doctorId = dto.prescribingDoctorId, let doctor = doctorMap[doctorId] {
                therapy.prescribingDoctor = doctor
            }

            // Sync doses
            for doseDTO in dto.doses {
                let dose = Dose(context: context)
                dose.id = doseDTO.id
                dose.time = Self.parseTimeOfDay(doseDTO.timeOfDay)
                dose.amount = NSNumber(value: doseDTO.amount)
                dose.therapy = therapy
            }
        }

        // --- Sync stocks ---
        for dto in response.stocks {
            guard let medicine = medicineMap[dto.trackedMedicineId],
                  let package = packageMap[dto.trackedPackageId] else { continue }
            let stock = Stock(context: context)
            stock.id = dto.id
            stock.stock_units = Int32(dto.stockUnits)
            stock.context_key = dto.contextKey
            stock.updated_at = Date()
            stock.medicine = medicine
            stock.package = package
        }

        // --- Sync activity logs ---
        for dto in response.activityLogs {
            // Log.medicine is required — skip if we can't resolve
            guard let medId = dto.trackedMedicineId,
                  let medicine = medicineMap[medId] else { continue }
            let logEntry = Log(context: context)
            logEntry.id = dto.id
            logEntry.type = dto.type
            logEntry.timestamp = dto.timestamp
            logEntry.operation_id = dto.operationId
            logEntry.reversal_of_operation_id = dto.reversalOfOperationId
            logEntry.scheduled_due_at = dto.scheduledDueAt
            logEntry.source = dto.source
            logEntry.medicine = medicine
            if let pkgId = dto.trackedPackageId, let package = packageMap[pkgId] {
                logEntry.package = package
            }
        }

        // --- Sync dose events ---
        for dto in response.doseEvents {
            let event = DoseEventRecord(context: context)
            event.id = dto.id
            event.due_at = dto.dueAt
            event.status = dto.status
            if let medId = dto.trackedMedicineId, let medicine = medicineMap[medId] {
                event.medicine = medicine
            }
        }

        // --- Sync monitoring measurements ---
        for dto in response.monitoringMeasurements {
            let measurement = MonitoringMeasurement(context: context)
            measurement.id = dto.id
            measurement.kind = dto.type
            measurement.value_primary = NSNumber(value: dto.value)
            measurement.unit = dto.unit
            measurement.measured_at = dto.measuredAt
            measurement.created_at = dto.measuredAt
            measurement.scheduled_at = dto.scheduledAt
            measurement.todo_source_id = dto.id.uuidString
            if let medId = dto.trackedMedicineId, let medicine = medicineMap[medId] {
                measurement.medicine = medicine
            }
        }

        // --- Save ---
        if context.hasChanges {
            try context.save()
        }
    }

    // MARK: - Helpers

    private func clearOperationalData() {
        let entityNames = [
            "MonitoringMeasurement", "DoseEventRecord", "Log", "Stock",
            "Dose", "Therapy", "MedicinePackage", "Package", "Medicine",
            "Cabinet", "Doctor", "Person"
        ]
        for entityName in entityNames {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs
            do {
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                        into: [context]
                    )
                }
            } catch {
                print("[FastAPIDataSync] Failed to clear \(entityName): \(error)")
            }
        }
    }

    /// Build an iCalendar RRULE string from the API's separate recurrence fields.
    private func buildRruleString(from dto: FastAPITherapyWithDoses) -> String? {
        guard let freq = dto.freq else { return nil }
        var parts = ["FREQ=\(freq.uppercased())"]
        if let interval = dto.interval, interval > 1 {
            parts.append("INTERVAL=\(interval)")
        }
        if let count = dto.count {
            parts.append("COUNT=\(count)")
        }
        if let until = dto.until {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            fmt.timeZone = TimeZone(identifier: "UTC")
            parts.append("UNTIL=\(fmt.string(from: until))")
        }
        if let byDay = dto.byDay, !byDay.isEmpty {
            parts.append("BYDAY=\(byDay.joined(separator: ","))")
        }
        if let cycleOn = dto.cycleOnDays, cycleOn > 0 {
            parts.append("X-PHARMAPP-ON=\(cycleOn)")
        }
        if let cycleOff = dto.cycleOffDays, cycleOff > 0 {
            parts.append("X-PHARMAPP-OFF=\(cycleOff)")
        }
        return "RRULE:" + parts.joined(separator: ";")
    }

    /// Parse "HH:mm" time string into a Date (today at that time).
    nonisolated private static func parseTimeOfDay(_ timeString: String) -> Date {
        let parts = timeString.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return Date()
        }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Incremental Sync Helpers (for write-through)

    /// After a successful API write, update Core Data to reflect the change.
    func refreshFromBootstrap() async throws {
        try await performBootstrapSync()
    }
}
