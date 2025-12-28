import SwiftUI
import CoreData

/// ViewModel dedicato al tab "Armadietto".
class CabinetViewModel: ObservableObject {
    // Stato di selezione (solo per il tab Armadietto)
    @Published var selectedMedicines: Set<Medicine> = []
    @Published var isSelecting: Bool = false

    let actionService: MedicineActionService

    init(actionService: MedicineActionService = MedicineActionService()) {
        self.actionService = actionService
    }

    // MARK: - Selection
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

    func clearSelection() {
        DispatchQueue.main.async {
            self.selectedMedicines.removeAll()
            self.isSelecting = false
        }
    }

    struct ShelfEntry: Identifiable {
        enum Kind {
            case cabinet(Cabinet)
            case medicine(Medicine)
        }
        let id: NSManagedObjectID
        let priority: Int
        let name: String
        let kind: Kind
    }

    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    /// Sezioni ordinate per List (cabinet e medicinali fuori da cabinet).
    func shelfEntries(
        medicines: [Medicine],
        logs: [Log],
        option: Option?,
        cabinets: [Cabinet]
    ) -> [ShelfEntry] {
        let sections = computeSections(for: medicines, logs: logs, option: option)
        let orderedMeds = sections.purchase + sections.oggi + sections.ok

        var indexMap: [NSManagedObjectID: Int] = [:]
        for (idx, med) in orderedMeds.enumerated() {
            indexMap[med.objectID] = idx
        }

        var entries: [ShelfEntry] = []
        for med in orderedMeds where med.cabinet == nil {
            let priority = indexMap[med.objectID] ?? Int.max
            entries.append(ShelfEntry(id: med.objectID, priority: priority, name: med.nome, kind: .medicine(med)))
        }

        let baseIndex = orderedMeds.count
        for (cabIdx, cabinet) in cabinets.enumerated() {
            let meds = cabinet.medicines
            let idxs = meds.compactMap { indexMap[$0.objectID] }
            let priority = idxs.min() ?? (baseIndex + cabIdx)
            entries.append(ShelfEntry(id: cabinet.objectID, priority: priority, name: cabinet.name, kind: .cabinet(cabinet)))
        }
        return entries.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.priority < rhs.priority
        }
    }

    func sortedMedicines(in cabinet: Cabinet) -> [Medicine] {
        cabinet.medicines.sorted { lhs, rhs in
            let left = lhs.nome.lowercased()
            let right = rhs.nome.lowercased()
            return left < right
        }
    }

    func shouldShowPrescriptionAction(for medicine: Medicine) -> Bool {
        guard medicine.obbligo_ricetta else { return false }
        if medicine.hasNewPrescritpionRequest() { return false }
        let rec = RecurrenceManager(context: viewContext)
        return needsPrescriptionBeforePurchase(medicine, recurrenceManager: rec)
    }

    func package(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
                return package
            }
        }
        if let package = medicine.packages.first {
            return package
        }
        return nil
    }
}
