import Foundation
import CoreData

struct IntakeGuardrailWarning {
    let title: String
    let message: String
}

struct IntakeDecision {
    let warning: IntakeGuardrailWarning?
    let therapy: Therapy?
}

enum IntakeGuardrailResult {
    case allowed(Log?)
    case requiresConfirmation(IntakeGuardrailWarning, therapy: Therapy?)
}

/// Servizio che incapsula le azioni di dominio sui medicinali (log di assunzione, acquisto, ricetta).
final class MedicineActionService {
    private let context: NSManagedObjectContext
    private let clock: Clock
    private lazy var stockService = StockService(context: context)
    private lazy var eventStore: EventStore = CoreDataEventStore(context: context)
    private lazy var recordPurchaseUseCase = RecordPurchaseUseCase(eventStore: eventStore, clock: clock)
    private lazy var requestPrescriptionUseCase = RequestPrescriptionUseCase(eventStore: eventStore, clock: clock)
    private lazy var recordPrescriptionReceivedUseCase = RecordPrescriptionReceivedUseCase(eventStore: eventStore, clock: clock)
    private lazy var undoActionUseCase = UndoActionUseCase(eventStore: eventStore, clock: clock)

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext, clock: Clock = SystemClock()) {
        self.context = context
        self.clock = clock
    }

    // MARK: - API pubblica
    @discardableResult
    func requestPrescription(for medicine: Medicine, operationId: UUID) -> Log? {
        guard let package = package(for: medicine) else { return nil }
        let request = RequestPrescriptionRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            packageId: PackageId(package.id)
        )
        do {
            _ = try requestPrescriptionUseCase.execute(request)
            return existingLog(operationId: operationId)
        } catch {
            print("⚠️ requestPrescription: \(error)")
            return nil
        }
    }

    @discardableResult
    func requestPrescription(for entry: MedicinePackage, operationId: UUID) -> Log? {
        let request = RequestPrescriptionRequest(
            operationId: operationId,
            medicineId: MedicineId(entry.medicine.id),
            packageId: PackageId(entry.package.id)
        )
        do {
            _ = try requestPrescriptionUseCase.execute(request)
            return existingLog(operationId: operationId)
        } catch {
            print("⚠️ requestPrescription: \(error)")
            return nil
        }
    }

    @discardableResult
    func markPrescriptionReceived(for medicine: Medicine, operationId: UUID) -> Log? {
        guard let package = package(for: medicine) else { return nil }
        let request = RecordPrescriptionReceivedRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            packageId: PackageId(package.id)
        )
        do {
            _ = try recordPrescriptionReceivedUseCase.execute(request)
            return existingLog(operationId: operationId)
        } catch {
            print("⚠️ markPrescriptionReceived: \(error)")
            return nil
        }
    }

    @discardableResult
    func markPrescriptionReceived(for entry: MedicinePackage, operationId: UUID) -> Log? {
        let request = RecordPrescriptionReceivedRequest(
            operationId: operationId,
            medicineId: MedicineId(entry.medicine.id),
            packageId: PackageId(entry.package.id)
        )
        do {
            _ = try recordPrescriptionReceivedUseCase.execute(request)
            return existingLog(operationId: operationId)
        } catch {
            print("⚠️ markPrescriptionReceived: \(error)")
            return nil
        }
    }

    @discardableResult
    func markAsPurchased(for medicine: Medicine, operationId: UUID) -> Log? {
        guard let package = package(for: medicine) else { return nil }
        let request = RecordPurchaseRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            packageId: PackageId(package.id)
        )
        do {
            _ = try recordPurchaseUseCase.execute(request)
            return existingLog(operationId: operationId)
        } catch {
            print("⚠️ markAsPurchased: \(error)")
            return nil
        }
    }

    @discardableResult
    func markAsPurchased(for entry: MedicinePackage, operationId: UUID) -> Log? {
        let request = RecordPurchaseRequest(
            operationId: operationId,
            medicineId: MedicineId(entry.medicine.id),
            packageId: PackageId(entry.package.id)
        )
        do {
            _ = try recordPurchaseUseCase.execute(request)
            return existingLog(operationId: operationId)
        } catch {
            print("⚠️ markAsPurchased: \(error)")
            return nil
        }
    }

    @discardableResult
    func markAsTaken(for medicine: Medicine, operationId: UUID) -> Log? {
        let therapy = resolveTherapyCandidate(for: medicine, now: Date())
        return addIntakeLog(for: medicine, therapy: therapy, operationId: operationId)
    }

    @discardableResult
    func markAsTaken(for entry: MedicinePackage, operationId: UUID) -> Log? {
        let therapy = resolveTherapyCandidate(for: entry, now: Date())
        if let therapy {
            return addLog(for: entry.medicine, package: entry.package, type: "intake", therapy: therapy, operationId: operationId)
        }
        return addLog(for: entry.medicine, package: entry.package, type: "intake", operationId: operationId)
    }

    @discardableResult
    func markAsTaken(for therapy: Therapy, operationId: UUID) -> Log? {
        addIntakeLog(for: therapy.medicine, therapy: therapy, operationId: operationId)
    }

    func guardedMarkAsTaken(for medicine: Medicine, operationId: UUID, now: Date = Date()) -> IntakeGuardrailResult {
        let therapy = resolveTherapyCandidate(for: medicine, now: now)
        if let warning = intakeGuardrailWarning(for: medicine, therapy: therapy, now: now) {
            return .requiresConfirmation(warning, therapy: therapy)
        }
        return .allowed(addIntakeLog(for: medicine, therapy: therapy, operationId: operationId))
    }

    func guardedMarkAsTaken(for entry: MedicinePackage, operationId: UUID, now: Date = Date()) -> IntakeGuardrailResult {
        let therapy = resolveTherapyCandidate(for: entry, now: now)
        if let warning = intakeGuardrailWarning(for: entry.medicine, therapy: therapy, now: now) {
            return .requiresConfirmation(warning, therapy: therapy)
        }
        if let therapy {
            return .allowed(addLog(for: entry.medicine, package: entry.package, type: "intake", therapy: therapy, operationId: operationId))
        }
        return .allowed(addLog(for: entry.medicine, package: entry.package, type: "intake", operationId: operationId))
    }

    func guardedMarkAsTaken(for therapy: Therapy, operationId: UUID, now: Date = Date()) -> IntakeGuardrailResult {
        if let warning = intakeGuardrailWarning(for: therapy.medicine, therapy: therapy, now: now) {
            return .requiresConfirmation(warning, therapy: therapy)
        }
        return .allowed(addIntakeLog(for: therapy.medicine, therapy: therapy, operationId: operationId))
    }

    func intakeDecision(for medicine: Medicine, now: Date = Date()) -> IntakeDecision {
        let therapy = resolveTherapyCandidate(for: medicine, now: now)
        let warning = intakeGuardrailWarning(for: medicine, therapy: therapy, now: now)
        return IntakeDecision(warning: warning, therapy: therapy)
    }

    func intakeDecision(for therapy: Therapy, now: Date = Date()) -> IntakeDecision {
        let warning = intakeGuardrailWarning(for: therapy.medicine, therapy: therapy, now: now)
        return IntakeDecision(warning: warning, therapy: therapy)
    }

    @discardableResult
    func undoLog(operationId: UUID) -> Bool {
        do {
            _ = try undoActionUseCase.execute(
                UndoActionRequest(
                    originalOperationId: operationId,
                    undoOperationId: UUID()
                )
            )
            return true
        } catch let error as PharmaError {
            if error.code == .invalidInput || error.code == .notFound {
                return stockService.undoLog(operationId: operationId)
            }
        } catch {
            return stockService.undoLog(operationId: operationId)
        }
        return stockService.undoLog(operationId: operationId)
    }

    @discardableResult
    func undoLog(logObjectID: NSManagedObjectID) -> Bool {
        guard let log = try? context.existingObject(with: logObjectID) as? Log else { return false }
        if let operationId = log.operation_id {
            return undoLog(operationId: operationId)
        }
        return stockService.undoLog(log)
    }

    // MARK: - Helpers
    private func package(for medicine: Medicine) -> Package? {
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

    private func resolveTherapyCandidate(for entry: MedicinePackage, now: Date) -> Therapy? {
        let therapies = therapies(for: entry)
        guard !therapies.isEmpty else { return nil }
        let recurrenceManager = RecurrenceManager(context: context)

        let candidates: [(therapy: Therapy, date: Date)] = therapies.compactMap { therapy in
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? now
            guard let next = recurrenceManager.nextOccurrence(rule: rule, startDate: start, after: now, doses: therapy.doses as NSSet?) else {
                return nil
            }
            return (therapy, next)
        }

        if let chosen = candidates.min(by: { $0.date < $1.date }) {
            return chosen.therapy
        }

        return therapies.first
    }

    private func therapies(for entry: MedicinePackage) -> [Therapy] {
        if let set = entry.therapies, !set.isEmpty {
            return Array(set)
        }
        let all = entry.medicine.therapies as? Set<Therapy> ?? []
        return all.filter { $0.package == entry.package }
    }

    private func resolveTherapyCandidate(for medicine: Medicine, now: Date) -> Therapy? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let recurrenceManager = RecurrenceManager(context: context)

        let candidates: [(therapy: Therapy, date: Date)] = therapies.compactMap { therapy in
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? now
            guard let next = recurrenceManager.nextOccurrence(rule: rule, startDate: start, after: now, doses: therapy.doses as NSSet?) else {
                return nil
            }
            return (therapy, next)
        }

        if let chosen = candidates.min(by: { $0.date < $1.date }) {
            return chosen.therapy
        }

        return therapies.first
    }

    private func addIntakeLog(for medicine: Medicine, therapy: Therapy?, operationId: UUID) -> Log? {
        if let therapy {
            return addLog(for: medicine, package: therapy.package, type: "intake", therapy: therapy, operationId: operationId)
        }
        guard let package = package(for: medicine) else { return nil }
        return addLog(for: medicine, package: package, type: "intake", operationId: operationId)
    }

    private func intakeGuardrailWarning(for medicine: Medicine, therapy: Therapy?, now: Date) -> IntakeGuardrailWarning? {
        nil
    }

    private func intakeCountToday(for therapy: Therapy?, medicine: Medicine, now: Date) -> Int {
        let calendar = Calendar.current
        let logsToday = medicine.effectiveIntakeLogs(on: now, calendar: calendar)
        guard let therapy else { return logsToday.count }
        let assigned = logsToday.filter { $0.therapy == therapy }.count
        if assigned > 0 { return assigned }

        let unassigned = logsToday.filter { $0.therapy == nil }
        let therapyCount = medicine.therapies?.count ?? 0
        if therapyCount == 1 { return unassigned.count }
        return unassigned.filter { $0.package == therapy.package }.count
    }

    private func lastIntakeLog(for therapy: Therapy?, medicine: Medicine) -> Log? {
        let logs = medicine.effectiveIntakeLogs()
        guard let therapy else {
            return logs.max(by: { $0.timestamp < $1.timestamp })
        }
        let assigned = logs.filter { $0.therapy == therapy }
        if let lastAssigned = assigned.max(by: { $0.timestamp < $1.timestamp }) {
            return lastAssigned
        }
        let unassigned = logs.filter { $0.therapy == nil }
        let therapyCount = medicine.therapies?.count ?? 0
        if therapyCount == 1 {
            return unassigned.max(by: { $0.timestamp < $1.timestamp })
        }
        return unassigned.filter { $0.package == therapy.package }.max(by: { $0.timestamp < $1.timestamp })
    }

    @discardableResult
    private func addLog(
        for medicine: Medicine,
        package: Package,
        type: String,
        therapy: Therapy? = nil,
        operationId: UUID
    ) -> Log? {
        return stockService.createLog(
            type: type,
            medicine: medicine,
            package: package,
            therapy: therapy,
            operationId: operationId
        )
    }

    private func existingLog(operationId: UUID) -> Log? {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.fetchLimit = 1
        request.includesSubentities = false
        request.predicate = NSPredicate(format: "operation_id == %@", operationId as CVarArg)
        return try? context.fetch(request).first
    }
}
