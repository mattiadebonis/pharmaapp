import SwiftUI
import CoreData

class FeedViewModel: ObservableObject {
    @Published var selectedMedicines: Set<Medicine> = []
    @Published var isSelecting: Bool = false
    private let context: NSManagedObjectContext = PersistenceController.shared.container.viewContext


    func enterSelectionMode(with medicine: Medicine) {
        isSelecting = true
        selectedMedicines.insert(medicine)
    }
    
    func toggleSelection(for medicine: Medicine) {
        if selectedMedicines.contains(medicine) {
            selectedMedicines.remove(medicine)
            if selectedMedicines.isEmpty {
                isSelecting = false
            }
        } else {
            selectedMedicines.insert(medicine)
        }
    }

    func cancelSelection() {
        selectedMedicines.removeAll()
        isSelecting = false
    }

    // MARK: - Core Data Operations

    func requestPrescription() {
        for medicine in selectedMedicines {
            requestPrescription(for: medicine)
        }
        clearSelection()
    }

    @discardableResult
    func requestPrescription(for medicine: Medicine) -> Log? {
        guard let package = getPackage(for: medicine) else { return nil }
        return addNewPrescriptionRequest(for: medicine, for: package)
    }

    func markAsPurchased() {
        for medicine in selectedMedicines {
            markAsPurchased(for: medicine)
        }
        clearSelection()
    }

    @discardableResult
    func markAsPurchased(for medicine: Medicine) -> Log? {
        guard let package = getPackage(for: medicine) else { return nil }
        return addPurchase(for: medicine, for: package)
    }

    @discardableResult
    func markPrescriptionReceived(for medicine: Medicine) -> Log? {
        guard let package = getPackage(for: medicine) else { return nil }
        return addPrescriptionReceived(for: medicine, for: package)
    }

    func markAsTaken() {
        for medicine in selectedMedicines {
            markAsTaken(for: medicine)
        }
        clearSelection()
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
                return addIntake(for: medicine, for: chosen.therapy.package, therapy: chosen.therapy)
            }

            if let fallback = therapies.first {
                return addIntake(for: medicine, for: fallback.package, therapy: fallback)
            }
        }

        guard let package = getPackage(for: medicine) else { return nil }
        return addIntake(for: medicine, for: package)
    }

    @discardableResult
    func markAsTaken(for therapy: Therapy) -> Log? {
        addIntake(for: therapy.medicine, for: therapy.package, therapy: therapy)
    }

    func clearSelection() {
        DispatchQueue.main.async {
            self.selectedMedicines.removeAll()
            self.isSelecting = false
        }
    }

    // MARK: - Helper Functions

    private func getPackage(for medicine: Medicine) -> Package? {
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
    private func addNewPrescriptionRequest(for medicine: Medicine, for package: Package) -> Log? {
        addLog(for: medicine, for: package, type: "new_prescription_request")
    }

    @discardableResult
    private func addPrescriptionReceived(for medicine: Medicine, for package: Package) -> Log? {
        addLog(for: medicine, for: package, type: "new_prescription")
    }

    @discardableResult
    private func addPurchase(for medicine: Medicine, for package: Package) -> Log? {
        addLog(for: medicine, for: package, type: "purchase")
    }

    @discardableResult
    private func addIntake(for medicine: Medicine, for package: Package, therapy: Therapy? = nil) -> Log? {
        addLog(for: medicine, for: package, type: "intake", therapy: therapy)
    }

    @discardableResult
    private func addLog(for medicine: Medicine, for package: Package, type: String, therapy: Therapy? = nil) -> Log? {
        let newLog = Log(context: context)
        newLog.id = UUID()
        newLog.type = type
        newLog.timestamp = Date()
        newLog.medicine = medicine
        newLog.package = package
        newLog.therapy = therapy

        do {
            try context.save()
            print("✅ Log saved: \(type) for \(medicine.nome ?? "Unknown Medicine")")
            return newLog
        } catch {
            context.delete(newLog)
            print("❌ Error saving log: \(error.localizedDescription)")
            return nil
        }
    }

    var allRequirePrescription: Bool {
        selectedMedicines.allSatisfy { $0.obbligo_ricetta }
    }
}
