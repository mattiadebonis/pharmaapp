import Foundation
import CoreData

private struct CoreDataCatalogGateway: CatalogGateway {}
private struct CoreDataPeopleGateway: PeopleGateway {}

@MainActor
private final class CoreDataIntentsGateway: IntentsGateway {
    private let facade: SiriIntentFacade

    init(facade: SiriIntentFacade) {
        self.facade = facade
    }

    func queueRoute(_ route: AppRoute) {
        facade.queueRoute(route)
    }

    func suggestedMedicines(limit: Int) -> [MedicineIntentEntity] {
        facade.suggestedMedicines(limit: limit)
    }

    func medicines(matching query: String, limit: Int) -> [MedicineIntentEntity] {
        facade.medicines(matching: query, limit: limit)
    }

    func medicines(withIDs ids: [String]) -> [MedicineIntentEntity] {
        facade.medicines(withIDs: ids)
    }

    func markTaken(medicineID: String) -> SiriActionExecution {
        facade.markTaken(medicineID: medicineID)
    }

    func markPurchased(medicineID: String) -> SiriActionExecution {
        facade.markPurchased(medicineID: medicineID)
    }

    func markPrescriptionReceived(medicineID: String) -> SiriActionExecution {
        facade.markPrescriptionReceived(medicineID: medicineID)
    }

    func nextDoseNow(now: Date) -> SiriNextDoseNow? {
        facade.nextDoseNow(now: now)
    }

    func doneTodayStatus(now: Date) -> SiriDoneTodayStatus {
        facade.doneTodayStatus(now: now)
    }

    func purchaseSummary(maxItems: Int) -> SiriPurchaseSummary {
        facade.purchaseSummary(maxItems: maxItems)
    }
}

@MainActor
private final class CoreDataMedicinesGateway: MedicinesGateway {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchCabinetSnapshot() throws -> MedicinesCabinetSnapshot {
        MedicinesCabinetSnapshot(
            medicinePackages: try context.fetch(MedicinePackage.extractEntries()),
            options: try context.fetch(Option.extractOptions()),
            cabinets: try context.fetch(Cabinet.extractCabinets())
        )
    }

    func fetchCurrentOption() throws -> Option? {
        let request = Option.extractOptions()
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func fetchMedicineDetailSnapshot(
        medicine: Medicine,
        package: Package,
        medicinePackage: MedicinePackage?
    ) throws -> MedicinesDetailSnapshot {
        let medicine = inContext(medicine)
        let package = inContext(package)
        let medicinePackage = inContextOptional(medicinePackage)

        let therapyRequest = Therapy.extractTherapies()
        therapyRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Therapy.start_date, ascending: true)]
        if let medicinePackage {
            therapyRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "medicine == %@", medicinePackage.medicine),
                NSPredicate(format: "package == %@", medicinePackage.package)
            ])
        } else {
            therapyRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "medicine == %@", medicine),
                NSPredicate(format: "package == %@", package)
            ])
        }

        return MedicinesDetailSnapshot(
            options: try context.fetch(Option.extractOptions()),
            doctors: try context.fetch(Doctor.extractDoctors()),
            allMedicines: try context.fetch(Medicine.extractMedicines()),
            therapies: try context.fetch(therapyRequest),
            intakeLogs: try context.fetch(Log.extractIntakeLogsFiltered(medicine: medicine))
        )
    }

    func fetchTherapyFormSnapshot() throws -> MedicinesTherapyFormSnapshot {
        MedicinesTherapyFormSnapshot(
            persons: try context.fetch(Person.extractPersons(includeAccount: true)),
            doctors: try context.fetch(Doctor.extractDoctors())
        )
    }

    @discardableResult
    func createCabinet(name: String) throws -> Cabinet {
        let cabinet = Cabinet(context: context)
        cabinet.id = UUID()
        cabinet.name = name
        cabinet.created_at = Date()
        try CoreDataWriteCommand.saveOrRollback(context)
        return cabinet
    }

    func moveEntry(entryId: UUID, toCabinet cabinetId: UUID?) throws {
        guard let entry = fetchEntry(id: entryId) else { return }
        if let cabinetId {
            entry.cabinet = fetchCabinet(id: cabinetId)
        } else {
            entry.cabinet = nil
        }
        try CoreDataWriteCommand.saveOrRollback(context)
    }

    func hasSufficientStockForIntake(entryId: UUID) -> Bool {
        guard let entry = fetchEntry(id: entryId) else { return false }
        return StockService(context: context).unitsReadOnly(for: entry.package) > 0
    }

    func units(for package: Package) -> Int {
        StockService(context: context).units(for: inContext(package))
    }

    @discardableResult
    func addPurchase(medicine: Medicine, package: Package) -> Bool {
        MedicineStockService(context: context).addPurchase(
            medicine: inContext(medicine),
            package: inContext(package)
        ) != nil
    }

    func setStockUnits(medicine: Medicine, package: Package, targetUnits: Int) {
        MedicineStockService(context: context).setStockUnits(
            medicine: inContext(medicine),
            package: inContext(package),
            targetUnits: targetUnits
        )
    }

    func updateDeadline(
        medicine: Medicine,
        package: Package,
        preferredEntry: MedicinePackage?,
        month: Int?,
        year: Int?
    ) throws {
        let medicine = inContext(medicine)
        let package = inContext(package)
        let preferredEntry = inContextOptional(preferredEntry)
        let entry = preferredEntry ?? MedicinePackage.latestActiveEntry(for: medicine, package: package, in: context)
        guard let entry else { return }

        entry.updateDeadline(month: month, year: year)
        try CoreDataWriteCommand.saveOrRollback(context)
    }

    func setCustomStockThreshold(medicine: Medicine, threshold: Int32) throws {
        let medicine = inContext(medicine)
        medicine.custom_stock_threshold = threshold
        try CoreDataWriteCommand.saveOrRollback(context)
    }

    func deleteCabinet(cabinetId: UUID, moveToCabinetId: UUID?) throws {
        guard let cabinet = fetchCabinet(id: cabinetId) else { return }
        let targetCabinet = moveToCabinetId.flatMap { fetchCabinet(id: $0) }
        let entriesToUpdate = Array(cabinet.medicinePackages ?? [])
        for entry in entriesToUpdate {
            entry.cabinet = targetCabinet
        }
        context.delete(cabinet)
        try CoreDataWriteCommand.saveOrRollback(context)
    }

    func deletePackage(medicine: Medicine, package: Package) throws {
        let medicine = inContext(medicine)
        let package = inContext(package)

        let relatedTherapies = (package.therapies ?? []).filter { $0.medicine.id == medicine.id }
        let relatedEntries = (package.medicinePackages ?? []).filter { $0.medicine.id == medicine.id }

        let currentUnits = StockService(context: context).units(for: package)
        if currentUnits > 0 {
            MedicineStockService(context: context).setStockUnits(
                medicine: medicine,
                package: package,
                targetUnits: 0
            )
        }

        for therapy in relatedTherapies {
            if let doses = therapy.doses as? Set<Dose> {
                for dose in doses {
                    context.delete(dose)
                }
            }
            context.delete(therapy)
        }

        for entry in relatedEntries {
            context.delete(entry)
        }

        try CoreDataWriteCommand.saveOrRollback(context)
    }

    func deleteMedicine(_ medicine: Medicine) throws {
        let medicine = inContext(medicine)

        let relatedLogs = (medicine.logs as? Set<Log>) ?? []
        let relatedTherapies = (medicine.therapies as? Set<Therapy>) ?? []
        let relatedPackages = medicine.packages
        let relatedEntries = medicine.medicinePackages ?? []

        for log in relatedLogs {
            context.delete(log)
        }
        for therapy in relatedTherapies {
            if let doses = therapy.doses as? Set<Dose> {
                for dose in doses {
                    context.delete(dose)
                }
            }
            context.delete(therapy)
        }
        for package in relatedPackages {
            context.delete(package)
        }
        for entry in relatedEntries {
            context.delete(entry)
        }

        context.delete(medicine)
        try CoreDataWriteCommand.saveOrRollback(context)
    }

    func loadLogs(medicine: Medicine) throws -> [Log] {
        let medicine = inContext(medicine)
        let request = Log.extractLogs()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Log.timestamp, ascending: false)]
        request.predicate = NSPredicate(format: "medicine == %@", medicine)
        return try context.fetch(request)
    }

    func missedDoseCandidate(medicine: Medicine, package: Package?, now: Date) -> MissedDoseCandidate? {
        let medicine = inContext(medicine)
        let package = inContextOptional(package)
        return MedicineActionService(context: context).missedDoseCandidate(
            for: medicine,
            package: package,
            now: now
        )
    }

    @discardableResult
    func recordMissedDoseIntake(
        candidate: MissedDoseCandidate,
        takenAt: Date,
        nextAction: MissedDoseNextAction,
        operationId: UUID
    ) -> Bool {
        MedicineActionService(context: context).recordMissedDoseIntake(
            candidate: candidate,
            takenAt: takenAt,
            nextAction: nextAction,
            operationId: operationId
        ) != nil
    }

    @discardableResult
    func recordIntake(
        medicine: Medicine,
        package: Package,
        medicinePackage: MedicinePackage?,
        operationId: UUID
    ) -> Bool {
        let actionService = MedicineActionService(context: context)
        if let entry = inContextOptional(medicinePackage) {
            return actionService.markAsTaken(for: entry, operationId: operationId) != nil
        }
        return actionService.markAsTaken(
            for: inContext(medicine),
            package: inContext(package),
            operationId: operationId
        ) != nil
    }

    func createTherapy(_ input: TherapyWriteInput) throws {
        let resolved = resolvedTherapyWriteInput(from: input)
        let therapy = Therapy(context: context)
        therapy.id = UUID()
        therapy.medicine = resolved.medicine
        applyTherapyValues(therapy, input: resolved)
        try CoreDataWriteCommand.saveOrRollback(context)
    }

    func updateTherapy(_ therapy: Therapy, input: TherapyWriteInput) throws {
        let therapy = inContext(therapy)
        let resolved = resolvedTherapyWriteInput(from: input)
        applyTherapyValues(therapy, input: resolved)
        try CoreDataWriteCommand.saveOrRollback(context)
    }

    func deleteTherapy(_ therapy: Therapy) throws {
        let therapy = inContext(therapy)
        let doseEventsRequest = DoseEventRecord.fetchRequest(for: therapy)
        let measurementsRequest = MonitoringMeasurement.fetchRequest() as NSFetchRequest<MonitoringMeasurement>
        measurementsRequest.predicate = NSPredicate(format: "therapy == %@", therapy)
        let logsRequest = Log.fetchRequest() as! NSFetchRequest<Log>
        logsRequest.predicate = NSPredicate(format: "therapy == %@", therapy)

        let doseEvents = try context.fetch(doseEventsRequest)
        let measurements = try context.fetch(measurementsRequest)
        let logs = try context.fetch(logsRequest)

        for dose in therapy.doses ?? [] {
            context.delete(dose)
        }

        for doseEvent in doseEvents {
            context.delete(doseEvent)
        }

        for measurement in measurements {
            context.delete(measurement)
        }

        for log in logs {
            log.therapy = nil
        }

        context.delete(therapy)
        try CoreDataWriteCommand.saveOrRollback(context)
    }

    private func resolvedTherapyWriteInput(from input: TherapyWriteInput) -> ResolvedTherapyWriteInput {
        ResolvedTherapyWriteInput(
            medicine: inContext(input.medicine),
            package: inContext(input.package),
            medicinePackage: inContextOptional(input.medicinePackage),
            person: inContext(input.person),
            prescribingDoctor: inContextOptional(input.prescribingDoctor),
            freq: input.freq,
            interval: input.interval,
            until: input.until,
            count: input.count,
            byDay: input.byDay,
            cycleOnDays: input.cycleOnDays,
            cycleOffDays: input.cycleOffDays,
            startDate: input.startDate,
            doses: input.doses,
            importance: input.importance,
            manualIntake: input.manualIntake,
            notificationsSilenced: input.notificationsSilenced,
            notificationLevel: input.notificationLevel,
            snoozeMinutes: input.snoozeMinutes,
            clinicalRules: input.clinicalRules
        )
    }

    private func applyTherapyValues(_ therapy: Therapy, input: ResolvedTherapyWriteInput) {
        therapy.medicine = input.medicine
        therapy.package = input.package
        therapy.medicinePackage = input.medicinePackage
        therapy.importance = input.importance
        therapy.person = input.person
        therapy.prescribingDoctor = input.prescribingDoctor
        therapy.condizione = nil
        therapy.manual_intake_registration = input.manualIntake
        therapy.notifications_silenced = input.notificationsSilenced
        therapy.notification_level = input.notificationLevel.rawValue
        therapy.snooze_minutes = Int32(input.snoozeMinutes)
        therapy.clinicalRulesValue = input.clinicalRules

        var rule = RecurrenceRule(freq: input.freq ?? "DAILY")
        rule.interval = input.interval ?? 1
        rule.until = input.until
        rule.count = input.count
        rule.byDay = input.byDay
        rule.cycleOnDays = input.cycleOnDays
        rule.cycleOffDays = input.cycleOffDays

        therapy.rrule = RecurrenceManager(context: context).buildRecurrenceString(from: rule)
        therapy.start_date = input.startDate

        for dose in therapy.doses ?? [] {
            context.delete(dose)
        }

        for draft in input.doses {
            let dose = Dose(context: context)
            dose.id = draft.id
            dose.time = draft.time
            dose.amount = NSNumber(value: draft.amount)
            dose.therapy = therapy
        }
    }

    private struct ResolvedTherapyWriteInput {
        let medicine: Medicine
        let package: Package
        let medicinePackage: MedicinePackage?
        let person: Person
        let prescribingDoctor: Doctor?
        let freq: String?
        let interval: Int?
        let until: Date?
        let count: Int?
        let byDay: [String]
        let cycleOnDays: Int?
        let cycleOffDays: Int?
        let startDate: Date
        let doses: [TherapyDoseDraft]
        let importance: String
        let manualIntake: Bool
        let notificationsSilenced: Bool
        let notificationLevel: TherapyNotificationLevel
        let snoozeMinutes: Int
        let clinicalRules: ClinicalRules?
    }

    private func inContext<T: NSManagedObject>(_ object: T) -> T {
        if object.managedObjectContext === context {
            return object
        }
        return context.object(with: object.objectID) as! T
    }

    private func inContextOptional<T: NSManagedObject>(_ object: T?) -> T? {
        guard let object else { return nil }
        return inContext(object)
    }

    private func fetchEntry(id: UUID) -> MedicinePackage? {
        let request = MedicinePackage.extractEntries()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func fetchCabinet(id: UUID) -> Cabinet? {
        let request = Cabinet.extractCabinets()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }
}

@MainActor
private final class CoreDataSearchGateway: SearchGateway {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchSnapshot() throws -> SearchDataSnapshot {
        SearchDataSnapshot(
            medicines: try context.fetch(Medicine.extractMedicines()),
            medicineEntries: try context.fetch(MedicinePackage.extractEntries()),
            therapies: try context.fetch(Therapy.extractTherapies()),
            doctors: try context.fetch(Doctor.extractDoctors()),
            persons: try context.fetch(Person.extractPersons()),
            option: Option.current(in: context)
        )
    }

    func addCatalogSelectionToCabinet(_ selection: CatalogSelection) throws {
        _ = resolveCatalogContext(for: selection)
        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SearchGatewayError.persistence
        }
    }

    func prepareCatalogPackageEditor(_ selection: CatalogSelection) throws -> SearchCatalogStockEditorPreparation {
        let resolved = resolveCatalogContext(for: selection)
        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SearchGatewayError.persistence
        }

        let currentUnits = StockService(context: context).units(for: resolved.package)
        let defaultTarget = currentUnits + max(1, selection.units)
        let (month, year) = deadlineInputs(for: resolved.medicine, package: resolved.package)
        return SearchCatalogStockEditorPreparation(
            context: resolved,
            defaultTargetUnits: defaultTarget,
            deadlineMonth: month,
            deadlineYear: year
        )
    }

    func prepareCatalogTherapy(_ selection: CatalogSelection) throws -> SearchCatalogResolvedContext {
        let resolved = resolveCatalogContext(for: selection)
        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SearchGatewayError.persistence
        }
        return resolved
    }

    func applyCatalogStockEditor(
        _ resolved: SearchCatalogResolvedContext,
        targetUnits: Int,
        deadlineMonth: Int?,
        deadlineYear: Int?
    ) throws {
        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SearchGatewayError.persistence
        }

        let stockService = MedicineStockService(context: context)
        guard let purchaseOperationId = stockService.addPurchase(
            medicine: resolved.medicine,
            package: resolved.package
        ) else {
            context.rollback()
            throw SearchGatewayError.purchaseRegistrationFailed
        }

        guard let purchasedEntry = MedicinePackage.fetchByPurchaseOperationId(
            purchaseOperationId,
            in: context
        ) else {
            context.rollback()
            throw SearchGatewayError.purchasedEntryNotFound
        }

        purchasedEntry.updateDeadline(month: deadlineMonth, year: deadlineYear)
        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SearchGatewayError.persistence
        }

        stockService.setStockUnits(
            medicine: resolved.medicine,
            package: resolved.package,
            targetUnits: max(0, targetUnits)
        )
    }

    private func resolveCatalogContext(for selection: CatalogSelection) -> SearchCatalogResolvedContext {
        let resolved = CatalogSelectionResolver(context: context).resolveOrCreateContext(for: selection)
        return SearchCatalogResolvedContext(
            selection: selection,
            medicine: resolved.medicine,
            package: resolved.package,
            entry: resolved.entry
        )
    }

    private func deadlineInputs(for medicine: Medicine, package: Package) -> (month: String, year: String) {
        if let entry = MedicinePackage.latestActiveEntry(for: medicine, package: package, in: context),
           let info = entry.deadlineMonthYear {
            return (String(format: "%02d", info.month), String(info.year))
        }
        return ("", "")
    }
}

@MainActor
private final class CoreDataAdherenceGateway: AdherenceGateway {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchTherapies() throws -> [Therapy] {
        try context.fetch(Therapy.extractTherapies())
    }

    func fetchIntakeLogs() throws -> [Log] {
        let request = Log.extractLogs()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        request.predicate = NSPredicate(format: "type == 'intake' OR type == 'intake_undo'")
        return try context.fetch(request)
    }

    func fetchMedicines() throws -> [Medicine] {
        try context.fetch(Medicine.extractMedicines())
    }

    func fetchPurchaseLogs(since cutoff: Date) throws -> [Log] {
        let request = Log.extractPurchaseLogs()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        request.predicate = NSPredicate(format: "type == 'purchase' AND timestamp >= %@", cutoff as NSDate)
        return try context.fetch(request)
    }

    func fetchMonitoringMeasurements(from start: Date, to endExclusive: Date) throws -> [MonitoringMeasurement] {
        let request = MonitoringMeasurement.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "measured_at", ascending: true)]
        request.predicate = NSPredicate(
            format: "measured_at >= %@ AND measured_at < %@",
            start as NSDate,
            endExclusive as NSDate
        )
        return try context.fetch(request)
    }
}

@MainActor
private final class CoreDataSettingsGateway: SettingsGateway {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func listPersons(includeAccount: Bool) throws -> [SettingsPersonRecord] {
        let request = Person.extractPersons(includeAccount: includeAccount)
        request.sortDescriptors = [
            NSSortDescriptor(key: "is_account", ascending: false),
            NSSortDescriptor(key: "nome", ascending: true)
        ]

        do {
            let people = try context.fetch(request)
            var didMutateIDs = false
            let records = people.map { person in
                let id = ensurePersonID(person, didMutate: &didMutateIDs)
                return makePersonRecord(from: person, id: id)
            }
            if didMutateIDs {
                try CoreDataWriteCommand.saveOrRollback(context)
            }
            return records
        } catch {
            throw SettingsGatewayError.persistence(error.localizedDescription)
        }
    }

    func person(id: UUID) throws -> SettingsPersonRecord? {
        guard let person = fetchPerson(id: id) else { return nil }
        return makePersonRecord(from: person, id: id)
    }

    func listDoctors() throws -> [SettingsDoctorRecord] {
        let request = Doctor.extractDoctors()
        request.sortDescriptors = [NSSortDescriptor(key: "nome", ascending: true)]

        do {
            let doctors = try context.fetch(request)
            var didMutateIDs = false
            let records = doctors.map { doctor in
                let id = ensureDoctorID(doctor, didMutate: &didMutateIDs)
                return makeDoctorRecord(from: doctor, id: id)
            }
            if didMutateIDs {
                try CoreDataWriteCommand.saveOrRollback(context)
            }
            return records
        } catch {
            throw SettingsGatewayError.persistence(error.localizedDescription)
        }
    }

    func doctor(id: UUID) throws -> SettingsDoctorRecord? {
        guard let doctor = fetchDoctor(id: id) else { return nil }
        return makeDoctorRecord(from: doctor, id: id)
    }

    func therapyNotificationPreferences() throws -> TherapyNotificationSettings {
        let option = Option.current(in: context)
        return TherapyNotificationSettings(
            level: TherapyNotificationPreferences.normalizedLevel(rawValue: option?.therapy_notification_level),
            snoozeMinutes: TherapyNotificationPreferences.normalizedSnoozeMinutes(
                rawValue: Int(option?.therapy_snooze_minutes ?? 0)
            )
        )
    }

    @discardableResult
    func savePerson(_ input: PersonWriteInput) throws -> UUID {
        let person: Person
        if let id = input.id, let existing = fetchPerson(id: id) {
            person = existing
        } else {
            person = Person(context: context)
            person.id = input.id ?? UUID()
            person.is_account = input.isAccount
        }

        if person.id == nil {
            person.id = input.id ?? UUID()
        }
        person.nome = input.name
        person.cognome = nil
        person.condizione = nil
        person.is_account = input.isAccount
        person.codice_fiscale = input.codiceFiscale

        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SettingsGatewayError.persistence(error.localizedDescription)
        }
        return person.id ?? UUID()
    }

    func deletePerson(id: UUID) throws {
        guard let person = fetchPerson(id: id) else {
            throw SettingsGatewayError.notFound("Persona non trovata.")
        }
        do {
            try PersonDeletionService.shared.delete(person, in: context)
        } catch {
            throw SettingsGatewayError.persistence(error.localizedDescription)
        }
    }

    @discardableResult
    func saveDoctor(_ input: DoctorWriteInput) throws -> UUID {
        let doctor: Doctor
        if let id = input.id, let existing = fetchDoctor(id: id) {
            doctor = existing
        } else {
            doctor = Doctor(context: context)
            doctor.id = input.id ?? UUID()
        }

        if doctor.id == nil {
            doctor.id = input.id ?? UUID()
        }
        doctor.nome = input.name
        doctor.cognome = nil
        doctor.mail = input.email
        doctor.telefono = input.phone
        doctor.specializzazione = input.specialization
        doctor.scheduleDTO = input.schedule
        doctor.segreteria_nome = input.secretaryName
        doctor.segreteria_mail = input.secretaryEmail
        doctor.segreteria_telefono = input.secretaryPhone
        doctor.secretaryScheduleDTO = input.secretarySchedule

        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SettingsGatewayError.persistence(error.localizedDescription)
        }
        return doctor.id ?? UUID()
    }

    func deleteDoctor(id: UUID) throws {
        guard let doctor = fetchDoctor(id: id) else {
            throw SettingsGatewayError.notFound("Dottore non trovato.")
        }
        context.delete(doctor)
        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SettingsGatewayError.persistence(error.localizedDescription)
        }
    }

    func savePrescriptionMessageTemplate(doctorId: UUID, template: String?) throws {
        guard let doctor = fetchDoctor(id: doctorId) else {
            throw SettingsGatewayError.notFound("Dottore non trovato.")
        }
        let normalizedTemplate = PrescriptionMessageTemplateRenderer.resolvedTemplate(customTemplate: template)
        doctor.prescription_message_template = normalizedTemplate == PrescriptionMessageTemplateRenderer.defaultTemplate
            ? nil
            : normalizedTemplate
        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SettingsGatewayError.persistence(error.localizedDescription)
        }
    }

    func saveTherapyNotificationPreferences(level: TherapyNotificationLevel, snoozeMinutes: Int) throws {
        let option = Option.current(in: context) ?? makeDefaultOption()
        option.therapy_notification_level = level.rawValue
        option.therapy_snooze_minutes = Int32(
            TherapyNotificationPreferences.normalizedSnoozeMinutes(rawValue: snoozeMinutes)
        )

        do {
            try CoreDataWriteCommand.saveOrRollback(context)
        } catch {
            throw SettingsGatewayError.persistence(error.localizedDescription)
        }
    }

    private func fetchPerson(id: UUID) -> Person? {
        let request = Person.extractPersons(includeAccount: true)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func fetchDoctor(id: UUID) -> Doctor? {
        let request = Doctor.extractDoctors()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func ensurePersonID(_ person: Person, didMutate: inout Bool) -> UUID {
        if let id = person.id {
            return id
        }
        let generated = UUID()
        person.id = generated
        didMutate = true
        return generated
    }

    private func ensureDoctorID(_ doctor: Doctor, didMutate: inout Bool) -> UUID {
        if let id = doctor.id {
            return id
        }
        let generated = UUID()
        doctor.id = generated
        didMutate = true
        return generated
    }

    private func makePersonRecord(from person: Person, id: UUID) -> SettingsPersonRecord {
        SettingsPersonRecord(
            id: id,
            name: normalizedPersonName(from: person),
            codiceFiscale: normalizedText(person.codice_fiscale),
            isAccount: person.is_account
        )
    }

    private func makeDoctorRecord(from doctor: Doctor, id: UUID) -> SettingsDoctorRecord {
        SettingsDoctorRecord(
            id: id,
            name: normalizedDoctorName(from: doctor),
            email: normalizedText(doctor.mail),
            phone: normalizedText(doctor.telefono),
            specialization: normalizedText(doctor.specializzazione),
            schedule: doctor.scheduleDTO,
            secretaryName: normalizedText(doctor.segreteria_nome),
            secretaryEmail: normalizedText(doctor.segreteria_mail),
            secretaryPhone: normalizedText(doctor.segreteria_telefono),
            secretarySchedule: doctor.secretaryScheduleDTO,
            prescriptionMessageTemplate: normalizedText(doctor.prescription_message_template)
        )
    }

    private func normalizedPersonName(from person: Person) -> String? {
        let first = normalizedText(person.nome)
        let last = normalizedText(person.cognome)
        let components = [first, last].compactMap { $0 }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: " ")
    }

    private func normalizedDoctorName(from doctor: Doctor) -> String? {
        let first = normalizedText(doctor.nome)
        let last = normalizedText(doctor.cognome)
        let components = [first, last].compactMap { $0 }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: " ")
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeDefaultOption() -> Option {
        let option = Option(context: context)
        option.id = UUID()
        option.manual_intake_registration = false
        option.day_threeshold_stocks_alarm = 7
        option.therapy_notification_level = TherapyNotificationPreferences.defaultLevel.rawValue
        option.therapy_snooze_minutes = Int32(TherapyNotificationPreferences.defaultSnoozeMinutes)
        option.prescription_message_template = PrescriptionMessageTemplateRenderer.defaultTemplate
        return option
    }
}

@MainActor
private final class CoreDataNotificationsGateway: NotificationsGateway {
    private let context: NSManagedObjectContext
    private let notificationCenter: NotificationCenter
    private let coordinator: NotificationCoordinator
    private let actionPerformer: CriticalDoseActionPerforming
    private let liveActivityRefresher: CriticalDoseLiveActivityRefreshing
    private var didStart = false
    private var didSaveObserver: NSObjectProtocol?

    init(
        context: NSManagedObjectContext,
        policy: PerformancePolicy = PerformancePolicy.current(),
        coordinator: NotificationCoordinator? = nil,
        actionPerformer: CriticalDoseActionPerforming? = nil,
        liveActivityRefresher: CriticalDoseLiveActivityRefreshing? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.context = context
        self.notificationCenter = notificationCenter
        self.coordinator = coordinator ?? NotificationCoordinator(policy: policy)
        self.actionPerformer = actionPerformer ?? CriticalDoseActionService(context: context)
        self.liveActivityRefresher = liveActivityRefresher ?? CriticalDoseLiveActivityCoordinator.shared
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        coordinator.start()
        didSaveObserver = notificationCenter.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: context,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard Self.hasRelevantChanges(notification) else { return }
            self.coordinator.refreshAfterStoreChange(reason: "core-data")
        }
    }

    func refreshAfterStoreChange(reason: String) {
        coordinator.refreshAfterStoreChange(reason: reason)
    }

    func refreshCriticalLiveActivity(reason: String, now: Date?) async {
        _ = await liveActivityRefresher.refresh(reason: reason, now: now)
    }

    func markCriticalDoseTaken(contentState: CriticalDoseLiveActivityAttributes.ContentState) -> Bool {
        actionPerformer.markTaken(contentState: contentState)
    }

    func remindCriticalDoseLater(contentState: CriticalDoseLiveActivityAttributes.ContentState, now: Date) async -> Bool {
        await actionPerformer.remindLater(contentState: contentState, now: now)
    }

    func showCriticalDoseConfirmationThenRefresh(medicineName: String) async {
        await liveActivityRefresher.showConfirmationThenRefresh(medicineName: medicineName)
    }

    deinit {
        if let didSaveObserver {
            notificationCenter.removeObserver(didSaveObserver)
        }
    }

    nonisolated private static let relevantEntityNames: Set<String> = [
        "therapy",
        "dose",
        "stock",
        "log",
        "medicine",
        "medicinepackage",
        "package",
        "option"
    ]

    nonisolated private static func hasRelevantChanges(_ notification: Notification) -> Bool {
        let userInfo = notification.userInfo ?? [:]
        let changedObjects = [
            userInfo[NSInsertedObjectsKey],
            userInfo[NSUpdatedObjectsKey],
            userInfo[NSDeletedObjectsKey]
        ]
            .compactMap { $0 as? Set<NSManagedObject> }
            .flatMap(Array.init)

        guard !changedObjects.isEmpty else { return false }
        return changedObjects.contains { object in
            guard let name = object.entity.name?.lowercased() else { return false }
            return relevantEntityNames.contains(name)
        }
    }
}

@MainActor
final class CoreDataAppDataProvider: AppDataProvider {
    let backend: BackendType = .coredata

    let medicines: any MedicinesGateway
    let catalog: any CatalogGateway = CoreDataCatalogGateway()
    let search: any SearchGateway
    let adherence: any AdherenceGateway
    let people: any PeopleGateway = CoreDataPeopleGateway()
    let settings: any SettingsGateway
    let notifications: any NotificationsGateway
    let intents: any IntentsGateway

    let auth: any AuthGateway
    let backup: any BackupGateway

    private let notificationCenter: NotificationCenter
    private let context: NSManagedObjectContext

    init(
        authGateway: any AuthGateway,
        backupGateway: any BackupGateway,
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
        notificationCenter: NotificationCenter = .default
    ) {
        self.auth = authGateway
        self.backup = backupGateway
        self.context = context
        self.notificationCenter = notificationCenter
        self.medicines = CoreDataMedicinesGateway(context: context)
        self.search = CoreDataSearchGateway(context: context)
        self.adherence = CoreDataAdherenceGateway(context: context)
        self.settings = CoreDataSettingsGateway(context: context)
        self.notifications = CoreDataNotificationsGateway(context: context)
        self.intents = CoreDataIntentsGateway(facade: SiriIntentFacade())
    }

    func observe(scopes: Set<DataScope>) -> AsyncStream<DataChangeEvent> {
        let backupGateway = backup
        return AsyncStream { continuation in
            let didSaveObserver = notificationCenter.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: context,
                queue: .main
            ) { [scopes] notification in
                let changedScopes = Self.inferredScopes(from: notification)
                let affected = scopes.isEmpty
                    ? changedScopes
                    : changedScopes.intersection(scopes)
                for scope in affected {
                    continuation.yield(
                        DataChangeEvent(
                            scope: scope,
                            reason: "core-data-save",
                            at: Date()
                        )
                    )
                }
            }

            let shouldObserveBackup = scopes.isEmpty || scopes.contains(.backup)
            let backupObservationTask: Task<Void, Never>? = shouldObserveBackup
                ? Task { @MainActor in
                    var previousState = backupGateway.state
                    for await state in backupGateway.observeState() {
                        guard state != previousState else { continue }
                        let reason: String
                        if state.restoreRevision != previousState.restoreRevision {
                            reason = "backup-restore"
                        } else if state.status != previousState.status {
                            reason = "backup-status"
                        } else {
                            reason = "backup-state"
                        }
                        previousState = state
                        continuation.yield(
                            DataChangeEvent(
                                scope: .backup,
                                reason: reason,
                                at: Date()
                            )
                        )
                    }
                }
                : nil

            continuation.onTermination = { [notificationCenter] _ in
                notificationCenter.removeObserver(didSaveObserver)
                backupObservationTask?.cancel()
            }
        }
    }

    nonisolated private static func inferredScopes(from notification: Notification) -> Set<DataScope> {
        let userInfo = notification.userInfo ?? [:]
        let changedObjects = [
            userInfo[NSInsertedObjectsKey],
            userInfo[NSUpdatedObjectsKey],
            userInfo[NSDeletedObjectsKey]
        ]
            .compactMap { $0 as? Set<NSManagedObject> }
            .flatMap(Array.init)

        if changedObjects.isEmpty {
            return Set(DataScope.allCases)
        }

        var scopes = Set<DataScope>()
        for object in changedObjects {
            let name = object.entity.name?.lowercased() ?? ""
            switch name {
            case "medicine", "package", "medicinepackage":
                scopes.insert(.medicines)
            case "therapy", "dose":
                scopes.insert(.therapies)
            case "log":
                scopes.insert(.logs)
            case "stock":
                scopes.insert(.stocks)
            case "cabinet", "cabinetmembership":
                scopes.insert(.cabinets)
            case "person", "userprofile", "privateoverlay":
                scopes.insert(.people)
            case "doctor":
                scopes.insert(.doctors)
            case "option":
                scopes.insert(.options)
            case "doseevent", "notificationsettings", "notificationlock":
                scopes.insert(.notifications)
            default:
                continue
            }
        }

        return scopes.isEmpty ? Set(DataScope.allCases) : scopes
    }
}
