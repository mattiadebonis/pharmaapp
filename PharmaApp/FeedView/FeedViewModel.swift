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
            if let package = getPackage(for: medicine) {
                addNewPrescriptionRequest(for: medicine, for: package)
            }
        }
        clearSelection()
    }

    func markAsPurchased() {
        for medicine in selectedMedicines {
            if let package = getPackage(for: medicine) {
                addPurchase(for: medicine, for: package)
            }
        }
        clearSelection()
    }

    func markAsTaken() {
        for medicine in selectedMedicines {
            if let package = getPackage(for: medicine) {
                addIntake(for: medicine, for: package)
            }
        }
        clearSelection()
    }

    private func clearSelection() {
        DispatchQueue.main.async {
            self.selectedMedicines.removeAll()
            self.isSelecting = false
        }
    }

    // MARK: - Helper Functions

    private func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        } else if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            let sortedLogs = purchaseLogs.sorted { $0.timestamp > $1.timestamp }
            return sortedLogs.first?.package
        }
        return nil
    }

    private func addNewPrescriptionRequest(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, type: "new_prescription_request")
    }

    private func addPurchase(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, type: "purchase")
    }

    private func addIntake(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, type: "intake")
    }

    private func addLog(for medicine: Medicine, for package: Package, type: String) {
        let newLog = Log(context: context)
        newLog.id = UUID()
        newLog.type = type
        newLog.timestamp = Date()
        newLog.medicine = medicine
        newLog.package = package

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
