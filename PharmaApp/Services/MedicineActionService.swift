import Foundation
import CoreData

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
        if let therapies = medicine.therapies, !therapies.isEmpty {
            let recurrenceManager = RecurrenceManager(context: context)
            let now = Date()

            let candidates: [(therapy: Therapy, date: Date)] = therapies.compactMap { therapy in
                let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
                let start = therapy.start_date ?? now
                guard let next = recurrenceManager.nextOccurrence(rule: rule, startDate: start, after: now, doses: therapy.doses as NSSet?) else {
                    return nil
                }
                return (therapy, next)
            }

            if let chosen = candidates.min(by: { $0.date < $1.date }) {
                return addLog(for: medicine, package: chosen.therapy.package, type: "intake", therapy: chosen.therapy)
            }

            if let fallback = therapies.first {
                return addLog(for: medicine, package: fallback.package, type: "intake", therapy: fallback)
            }
        }

        guard let package = package(for: medicine) else { return nil }
        return addLog(for: medicine, package: package, type: "intake")
    }

    @discardableResult
    func markAsTaken(for therapy: Therapy) -> Log? {
        addLog(for: therapy.medicine, package: therapy.package, type: "intake", therapy: therapy)
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

    @discardableResult
    private func addLog(for medicine: Medicine, package: Package, type: String, therapy: Therapy? = nil) -> Log? {
        return stockService.createLog(type: type, medicine: medicine, package: package, therapy: therapy)
    }
}
