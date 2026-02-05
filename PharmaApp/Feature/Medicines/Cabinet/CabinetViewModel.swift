import SwiftUI
import CoreData

/// ViewModel dedicato al tab "Armadietto".
class CabinetViewModel: ObservableObject {
    // Stato di selezione (solo per il tab Armadietto)
    @Published var selectedEntries: Set<MedicinePackage> = []
    @Published var isSelecting: Bool = false

    let actionService: MedicineActionService

    init(actionService: MedicineActionService = MedicineActionService()) {
        self.actionService = actionService
    }

    // MARK: - Selection
    func enterSelectionMode(with entry: MedicinePackage) {
        isSelecting = true
        selectedEntries.insert(entry)
    }

    func toggleSelection(for entry: MedicinePackage) {
        if selectedEntries.contains(entry) {
            selectedEntries.remove(entry)
            if selectedEntries.isEmpty {
                isSelecting = false
            }
        } else {
            selectedEntries.insert(entry)
        }
    }

    func cancelSelection() {
        selectedEntries.removeAll()
        isSelecting = false
    }

    func clearSelection() {
        DispatchQueue.main.async {
            self.selectedEntries.removeAll()
            self.isSelecting = false
        }
    }

    struct ShelfEntry: Identifiable {
        enum Kind {
            case cabinet(Cabinet)
            case medicinePackage(MedicinePackage)
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
        entries: [MedicinePackage],
        logs: [Log],
        option: Option?,
        cabinets: [Cabinet]
    ) -> [ShelfEntry] {
        let orderedEntries = orderedMedicinePackages(
            entries: entries,
            logs: logs,
            option: option
        )

        var indexMap: [NSManagedObjectID: Int] = [:]
        for (idx, entry) in orderedEntries.enumerated() {
            indexMap[entry.objectID] = idx
        }

        var medicineEntries: [ShelfEntry] = []
        for entry in orderedEntries where entry.cabinet == nil {
            let priority = indexMap[entry.objectID] ?? Int.max
            let name = entry.medicine.nome
            medicineEntries.append(ShelfEntry(id: entry.objectID, priority: priority, name: name, kind: .medicinePackage(entry)))
        }

        let baseIndex = orderedEntries.count
        var cabinetEntries: [ShelfEntry] = []
        for (cabIdx, cabinet) in cabinets.enumerated() {
            let cabinetEntryItems = orderedEntries.filter { $0.cabinet?.objectID == cabinet.objectID }
            let idxs = cabinetEntryItems.compactMap { indexMap[$0.objectID] }
            let priority = idxs.min() ?? (baseIndex + cabIdx)
            cabinetEntries.append(ShelfEntry(id: cabinet.objectID, priority: priority, name: cabinet.displayName, kind: .cabinet(cabinet)))
        }

        let sorter: (ShelfEntry, ShelfEntry) -> Bool = { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.priority < rhs.priority
        }

        return (medicineEntries + cabinetEntries).sorted(by: sorter)
    }

    func sortedEntries(in cabinet: Cabinet, entries: [MedicinePackage], logs: [Log], option: Option?) -> [MedicinePackage] {
        let filtered = entries.filter { $0.cabinet?.objectID == cabinet.objectID }
        return orderedMedicinePackages(
            entries: filtered,
            logs: logs,
            option: option
        )
    }

    func shouldShowPrescriptionAction(for entry: MedicinePackage) -> Bool {
        let medicine = entry.medicine
        guard medicine.obbligo_ricetta else { return false }
        if medicine.hasEffectivePrescriptionReceived() { return false }
        if medicine.hasNewPrescritpionRequest() { return false }
        let rec = RecurrenceManager(context: viewContext)
        return needsPrescriptionBeforePurchase(medicine, recurrenceManager: rec)
    }

    // MARK: - Sorting
    private func orderedMedicinePackages(
        entries: [MedicinePackage],
        logs: [Log],
        option: Option?
    ) -> [MedicinePackage] {
        let sections = computeSections(for: entries, logs: logs, option: option)
        return sections.purchase + sections.oggi + sections.ok
    }

    private func therapies(for entry: MedicinePackage) -> [Therapy] {
        if let set = entry.therapies, !set.isEmpty {
            return Array(set)
        }
        let all = entry.medicine.therapies as? Set<Therapy> ?? []
        return all.filter { $0.package == entry.package }
    }
}
