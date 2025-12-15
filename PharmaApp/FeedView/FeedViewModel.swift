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

    func requestPrescription(for medicine: Medicine) {
        guard let package = getPackage(for: medicine) else { return }
        addNewPrescriptionRequest(for: medicine, for: package)
    }

    func markAsPurchased() {
        for medicine in selectedMedicines {
            markAsPurchased(for: medicine)
        }
        clearSelection()
    }

    func markAsPurchased(for medicine: Medicine) {
        guard let package = getPackage(for: medicine) else { return }
        addPurchase(for: medicine, for: package)
    }

    func markPrescriptionReceived(for medicine: Medicine) {
        guard let package = getPackage(for: medicine) else { return }
        addPrescriptionReceived(for: medicine, for: package)
    }

    func markAsTaken() {
        for medicine in selectedMedicines {
            markAsTaken(for: medicine)
        }
        clearSelection()
    }

    func markAsTaken(for medicine: Medicine) {
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
                addIntake(for: medicine, for: chosen.therapy.package, therapy: chosen.therapy)
                return
            }

            if let fallback = therapies.first {
                addIntake(for: medicine, for: fallback.package, therapy: fallback)
                return
            }
        }

        guard let package = getPackage(for: medicine) else { return }
        addIntake(for: medicine, for: package)
    }

    func markAsTaken(for therapy: Therapy) {
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

    private func addNewPrescriptionRequest(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, type: "new_prescription_request")
    }

    private func addPrescriptionReceived(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, type: "new_prescription")
    }

    private func addPurchase(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, type: "purchase")
    }

    private func addIntake(for medicine: Medicine, for package: Package, therapy: Therapy? = nil) {
        addLog(for: medicine, for: package, type: "intake", therapy: therapy)
    }

    private func addLog(for medicine: Medicine, for package: Package, type: String, therapy: Therapy? = nil) {
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
        } catch {
            print("❌ Error saving log: \(error.localizedDescription)")
        }
    }

    var allRequirePrescription: Bool {
        selectedMedicines.allSatisfy { $0.obbligo_ricetta }
    }
}
