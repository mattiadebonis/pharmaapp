import Foundation
import CoreData

struct SiriActionExecution {
    let succeeded: Bool
    let message: String
    let medicineName: String?
}

struct SiriNextDoseNow {
    let medicine: MedicineIntentEntity
    let scheduledAt: Date
    let doseSummary: String?
}

struct SiriDoneTodayStatus {
    let isDone: Bool
    let totalPlanned: Int
    let totalTaken: Int
    let missingMedicines: [String]
}

struct SiriPurchaseSummary {
    let items: [String]
    let totalCount: Int

    var remainingCount: Int {
        max(0, totalCount - items.count)
    }
}

final class SiriIntentFacade {
    static let shared = SiriIntentFacade()

    private let context: NSManagedObjectContext
    private let operationIdProvider: OperationIdProviding
    private let routeStore: PendingAppRouteStoring

    init(
        context: NSManagedObjectContext = {
            let background = PersistenceController.shared.container.newBackgroundContext()
            background.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            background.automaticallyMergesChangesFromParent = true
            return background
        }(),
        operationIdProvider: OperationIdProviding = OperationIdProvider.shared,
        routeStore: PendingAppRouteStoring = PendingAppRouteStore()
    ) {
        self.context = context
        self.operationIdProvider = operationIdProvider
        self.routeStore = routeStore
    }

    func queueRoute(_ route: AppRoute) {
        routeStore.save(route: route)
    }

    func suggestedMedicines(limit: Int = 50) -> [MedicineIntentEntity] {
        context.performAndWait {
            let request = Medicine.extractMedicines()
            request.fetchLimit = max(1, limit)
            let medicines = (try? context.fetch(request)) ?? []
            return medicines.map(makeMedicineEntity(from:))
        }
    }

    func medicines(matching query: String, limit: Int = 20) -> [MedicineIntentEntity] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return suggestedMedicines(limit: limit)
        }

        return context.performAndWait {
            let request = Medicine.extractMedicines()
            request.fetchLimit = max(1, limit)
            request.predicate = NSPredicate(format: "nome CONTAINS[cd] %@", normalized)
            let medicines = (try? context.fetch(request)) ?? []
            return medicines.map(makeMedicineEntity(from:))
        }
    }

    func medicines(withIDs ids: [String]) -> [MedicineIntentEntity] {
        let uuids = ids.compactMap(UUID.init(uuidString:))
        guard !uuids.isEmpty else { return [] }

        return context.performAndWait {
            let request = Medicine.extractMedicines()
            request.predicate = NSPredicate(format: "id IN %@", uuids)
            let medicines = (try? context.fetch(request)) ?? []
            return medicines.map(makeMedicineEntity(from:))
        }
    }

    func markTaken(medicineID: String) -> SiriActionExecution {
        executeWriteAction(medicineID: medicineID, action: .intake) { service, medicine, operationID in
            service.markAsTaken(for: medicine, operationId: operationID)
        }
    }

    func markPurchased(medicineID: String) -> SiriActionExecution {
        executeWriteAction(medicineID: medicineID, action: .purchase) { service, medicine, operationID in
            service.markAsPurchased(for: medicine, operationId: operationID)
        }
    }

    func markPrescriptionReceived(medicineID: String) -> SiriActionExecution {
        executeWriteAction(medicineID: medicineID, action: .prescriptionReceived) { service, medicine, operationID in
            service.markPrescriptionReceived(for: medicine, operationId: operationID)
        }
    }

    func nextDoseNow(now: Date = Date()) -> SiriNextDoseNow? {
        context.performAndWait {
            let provider = CoreDataTherapyPlanProvider(context: context)
            let medicines = fetchMedicines()
            let option = fetchCurrentOption()
            let state = provider.buildState(
                medicines: medicines,
                logs: fetchLogs(),
                option: option,
                completedTodoIDs: []
            )

            let therapyCandidates = state.computedTodos
                .filter { $0.category == .therapy }
                .compactMap { item -> (TodoItem, Date)? in
                    guard let date = provider.todoTimeDate(for: item, medicines: medicines, option: option, now: now) else {
                        return nil
                    }
                    return (item, date)
                }
                .sorted { lhs, rhs in lhs.1 < rhs.1 }

            guard let firstTherapyItem = (therapyCandidates.first(where: { $0.1 >= now }) ?? therapyCandidates.first)?.0 else {
                return nil
            }
            guard let medicine = resolveMedicine(for: firstTherapyItem) else { return nil }
            guard let date = provider.todoTimeDate(for: firstTherapyItem, medicines: medicines, option: option, now: now)
                ?? timeDate(from: state.timeLabel(for: firstTherapyItem), fallbackDetail: firstTherapyItem.detail, now: now) else {
                return nil
            }

            return SiriNextDoseNow(
                medicine: makeMedicineEntity(from: medicine),
                scheduledAt: date,
                doseSummary: doseSummary(for: medicine)
            )
        }
    }

    func doneTodayStatus(now: Date = Date()) -> SiriDoneTodayStatus {
        context.performAndWait {
            let recurrenceService = PureRecurrenceService()
            var totalPlanned = 0
            var totalTaken = 0
            var missing: [String] = []

            for medicine in fetchMedicines() {
                guard let therapies = medicine.therapies, !therapies.isEmpty else { continue }

                let plannedForMedicine = therapies.reduce(0) { partial, therapy in
                    let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
                    let start = therapy.start_date ?? now
                    let dosesPerDay = max(1, therapy.doses?.count ?? 1)
                    return partial + recurrenceService.allowedEvents(
                        on: now,
                        rule: rule,
                        startDate: start,
                        dosesPerDay: dosesPerDay,
                        calendar: .current
                    )
                }

                guard plannedForMedicine > 0 else { continue }
                totalPlanned += plannedForMedicine

                let takenForMedicine = medicine.effectiveIntakeLogs(on: now, calendar: .current).count
                totalTaken += min(takenForMedicine, plannedForMedicine)

                if takenForMedicine < plannedForMedicine {
                    missing.append(medicine.nome)
                }
            }

            return SiriDoneTodayStatus(
                isDone: missing.isEmpty,
                totalPlanned: totalPlanned,
                totalTaken: totalTaken,
                missingMedicines: missing
            )
        }
    }

    func purchaseSummary(maxItems: Int = 3) -> SiriPurchaseSummary {
        context.performAndWait {
            let provider = CoreDataTherapyPlanProvider(context: context)
            let medicines = fetchMedicines()
            let state = provider.buildState(
                medicines: medicines,
                logs: fetchLogs(),
                option: fetchCurrentOption(),
                completedTodoIDs: []
            )

            let ordered = state.computedTodos
                .filter { $0.category == .purchase }
                .map { $0.title }
            var unique: [String] = []
            var seen: Set<String> = []
            for title in ordered {
                if seen.insert(title).inserted {
                    unique.append(title)
                }
            }

            let limited = Array(unique.prefix(max(1, maxItems)))
            return SiriPurchaseSummary(items: limited, totalCount: unique.count)
        }
    }

    private func executeWriteAction(
        medicineID: String,
        action: OperationAction,
        executor: (MedicineActionService, Medicine, UUID) -> Log?
    ) -> SiriActionExecution {
        guard let id = UUID(uuidString: medicineID) else {
            return SiriActionExecution(succeeded: false, message: "Non ho riconosciuto il medicinale.", medicineName: nil)
        }

        return context.performAndWait {
            guard let medicine = fetchMedicine(by: id) else {
                return SiriActionExecution(
                    succeeded: false,
                    message: "Non trovo quel medicinale. Apri l'app per scegliere quello giusto.",
                    medicineName: nil
                )
            }

            let service = MedicineActionService(context: context)
            let packageID = resolvePackage(for: medicine)?.id
            let operationKey = OperationKey.medicineAction(
                action: action,
                medicineId: medicine.id,
                packageId: packageID,
                source: .siri
            )
            let operationID = operationIdProvider.operationId(for: operationKey, ttl: 3)
            let log = executor(service, medicine, operationID)

            if log != nil {
                return SiriActionExecution(
                    succeeded: true,
                    message: "Operazione completata per \(medicine.nome).",
                    medicineName: medicine.nome
                )
            }

            operationIdProvider.clear(operationKey)
            return SiriActionExecution(
                succeeded: false,
                message: "Non sono riuscito a completare l'operazione per \(medicine.nome).",
                medicineName: medicine.nome
            )
        }
    }

    private func fetchMedicines() -> [Medicine] {
        let request = Medicine.extractMedicines()
        return (try? context.fetch(request)) ?? []
    }

    private func fetchLogs() -> [Log] {
        let request = Log.extractLogs()
        return (try? context.fetch(request)) ?? []
    }

    private func fetchCurrentOption() -> Option? {
        let request = Option.extractOptions()
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchMedicine(by id: UUID) -> Medicine? {
        let request = Medicine.extractMedicines()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func resolveMedicine(for item: TodoItem) -> Medicine? {
        if let medicineID = item.medicineId {
            return fetchMedicine(by: medicineID.rawValue)
        }

        let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let request = Medicine.extractMedicines()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "nome ==[cd] %@", trimmedTitle)
        return try? context.fetch(request).first
    }

    private func resolvePackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        let purchaseLogs = medicine.effectivePurchaseLogs()
        if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
            return package
        }
        if !medicine.packages.isEmpty {
            return medicine.packages.sorted(by: { $0.numero > $1.numero }).first
        }
        return nil
    }

    private func makeMedicineEntity(from medicine: Medicine) -> MedicineIntentEntity {
        let dosage = resolvePackage(for: medicine).map(packageLabel)
        return MedicineIntentEntity(
            id: medicine.id.uuidString,
            name: medicine.nome,
            dosage: dosage
        )
    }

    private func packageLabel(_ package: Package) -> String {
        let value = package.valore
        let unit = package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        if value > 0 && !unit.isEmpty {
            return "\(value) \(unit)"
        }
        if value > 0 {
            return "\(value)"
        }
        return package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func doseSummary(for medicine: Medicine) -> String? {
        guard let therapy = medicine.therapies?.first else { return nil }
        let unit = doseUnit(for: therapy)

        if let common = therapy.commonDoseAmount {
            return doseText(amount: common, unit: unit)
        }

        if let firstDose = (therapy.doses as? Set<Dose>)?.sorted(by: { $0.time < $1.time }).first {
            return doseText(amount: firstDose.amountValue, unit: unit)
        }

        return nil
    }

    private func doseText(amount: Double, unit: String) -> String {
        let rounded = abs(amount.rounded() - amount) < 0.0001
        let amountText = rounded ? String(Int(amount.rounded())) : String(amount).replacingOccurrences(of: ".", with: ",")
        return "\(amountText) \(unit)"
    }

    private func doseUnit(for therapy: Therapy) -> String {
        let tipologia = therapy.package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tipologia.contains("capsul") { return "capsula" }
        if tipologia.contains("compress") { return "compressa" }
        let fallback = therapy.package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "unita" : fallback.lowercased()
    }

    private func timeDate(from label: TimeLabel?, fallbackDetail: String?, now: Date) -> Date? {
        switch label {
        case .time(let date):
            return date
        case .category, .none:
            break
        }

        guard let fallbackDetail,
              let match = fallbackDetail.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression)
        else {
            return nil
        }

        let value = String(fallbackDetail[match])
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return nil
        }

        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }
}
