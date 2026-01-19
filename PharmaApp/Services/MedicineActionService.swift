import Foundation
import CoreData

struct IntakeGuardrailWarning {
    let title: String
    let message: String
}

enum IntakeGuardrailResult {
    case allowed(Log?)
    case requiresConfirmation(IntakeGuardrailWarning, therapy: Therapy?)
}

/// Servizio che incapsula le azioni di dominio sui medicinali (log di assunzione, acquisto, ricetta).
final class MedicineActionService {
    private let context: NSManagedObjectContext
    private lazy var stockService = StockService(context: context)

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    // MARK: - API pubblica
    @discardableResult
    func requestPrescription(for medicine: Medicine) -> Log? {
        guard let package = package(for: medicine) else { return nil }
        return addLog(for: medicine, package: package, type: "new_prescription_request")
    }

    @discardableResult
    func markPrescriptionReceived(for medicine: Medicine) -> Log? {
        guard let package = package(for: medicine) else { return nil }
        return addLog(for: medicine, package: package, type: "new_prescription")
    }

    @discardableResult
    func markAsPurchased(for medicine: Medicine) -> Log? {
        guard let package = package(for: medicine) else { return nil }
        return addLog(for: medicine, package: package, type: "purchase")
    }

    @discardableResult
    func markAsTaken(for medicine: Medicine) -> Log? {
        let therapy = resolveTherapyCandidate(for: medicine, now: Date())
        return addIntakeLog(for: medicine, therapy: therapy)
    }

    @discardableResult
    func markAsTaken(for therapy: Therapy) -> Log? {
        addIntakeLog(for: therapy.medicine, therapy: therapy)
    }

    func guardedMarkAsTaken(for medicine: Medicine, now: Date = Date()) -> IntakeGuardrailResult {
        let therapy = resolveTherapyCandidate(for: medicine, now: now)
        if let warning = intakeGuardrailWarning(for: medicine, therapy: therapy, now: now) {
            return .requiresConfirmation(warning, therapy: therapy)
        }
        return .allowed(addIntakeLog(for: medicine, therapy: therapy))
    }

    func guardedMarkAsTaken(for therapy: Therapy, now: Date = Date()) -> IntakeGuardrailResult {
        if let warning = intakeGuardrailWarning(for: therapy.medicine, therapy: therapy, now: now) {
            return .requiresConfirmation(warning, therapy: therapy)
        }
        return .allowed(addIntakeLog(for: therapy.medicine, therapy: therapy))
    }

    // MARK: - Helpers
    private func package(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
                return package
            }
        }
        if !medicine.packages.isEmpty {
            return medicine.packages.sorted(by: { $0.numero > $1.numero }).first
        }
        return nil
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

    private func addIntakeLog(for medicine: Medicine, therapy: Therapy?) -> Log? {
        if let therapy {
            return addLog(for: medicine, package: therapy.package, type: "intake", therapy: therapy)
        }
        guard let package = package(for: medicine) else { return nil }
        return addLog(for: medicine, package: package, type: "intake")
    }

    private func intakeGuardrailWarning(for medicine: Medicine, therapy: Therapy?, now: Date) -> IntakeGuardrailWarning? {
        nil
    }

    private func intakeCountToday(for therapy: Therapy?, medicine: Medicine, now: Date) -> Int {
        let calendar = Calendar.current
        let logsToday = (medicine.logs ?? []).filter { $0.type == "intake" && calendar.isDate($0.timestamp, inSameDayAs: now) }
        guard let therapy else { return logsToday.count }
        let assigned = logsToday.filter { $0.therapy == therapy }.count
        if assigned > 0 { return assigned }

        let unassigned = logsToday.filter { $0.therapy == nil }
        let therapyCount = medicine.therapies?.count ?? 0
        if therapyCount == 1 { return unassigned.count }
        return unassigned.filter { $0.package == therapy.package }.count
    }

    private func lastIntakeLog(for therapy: Therapy?, medicine: Medicine) -> Log? {
        let logs = (medicine.logs ?? []).filter { $0.type == "intake" }
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
    private func addLog(for medicine: Medicine, package: Package, type: String, therapy: Therapy? = nil) -> Log? {
        return stockService.createLog(type: type, medicine: medicine, package: package, therapy: therapy)
    }
}
