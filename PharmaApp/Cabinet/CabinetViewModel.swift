import SwiftUI
import CoreData

enum CabinetSortOrder: String, CaseIterable, Identifiable {
    case relevance
    case byType
    case nextDose
    case stockDepletion

    var id: String { rawValue }

    static var selectableCases: [CabinetSortOrder] {
        [.byType, .nextDose, .stockDepletion]
    }

    var title: String {
        switch self {
        case .relevance:
            return "Rilevanza"
        case .byType:
            return "Per tipologia"
        case .nextDose:
            return "Dose imminente"
        case .stockDepletion:
            return "Fine scorte imminente"
        }
    }
}

/// ViewModel dedicato al tab "Armadietto".
class CabinetViewModel: ObservableObject {
    // Stato di selezione (solo per il tab Armadietto)
    @Published var selectedEntries: Set<MedicinePackage> = []
    @Published var isSelecting: Bool = false
    @Published var sortOrder: CabinetSortOrder = .byType

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
            cabinetEntries.append(ShelfEntry(id: cabinet.objectID, priority: priority, name: cabinet.name, kind: .cabinet(cabinet)))
        }

        let sorter: (ShelfEntry, ShelfEntry) -> Bool = { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.priority < rhs.priority
        }

        switch sortOrder {
        case .byType:
            return cabinetEntries.sorted(by: sorter) + medicineEntries.sorted(by: sorter)
        case .relevance, .nextDose, .stockDepletion:
            return (medicineEntries + cabinetEntries).sorted(by: sorter)
        }
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
        switch sortOrder {
        case .relevance, .byType:
            let sections = computeSections(for: entries, logs: logs, option: option)
            return sections.purchase + sections.oggi + sections.ok
        case .nextDose:
            let recurrenceManager = RecurrenceManager(context: viewContext)
            let now = Date()
            return sortByNextDose(
                entries,
                now: now,
                recurrenceManager: recurrenceManager
            )
        case .stockDepletion:
            let recurrenceManager = RecurrenceManager(context: viewContext)
            return sortByStockDepletion(
                entries,
                option: option,
                recurrenceManager: recurrenceManager
            )
        }
    }

    private func sortByNextDose(
        _ entries: [MedicinePackage],
        now: Date,
        recurrenceManager: RecurrenceManager
    ) -> [MedicinePackage] {
        entries.sorted { lhs, rhs in
            let d1 = nextDoseDate(for: lhs, now: now, recurrenceManager: recurrenceManager) ?? .distantFuture
            let d2 = nextDoseDate(for: rhs, now: now, recurrenceManager: recurrenceManager) ?? .distantFuture
            if d1 != d2 { return d1 < d2 }
            return lhs.medicine.nome.localizedCaseInsensitiveCompare(rhs.medicine.nome) == .orderedAscending
        }
    }

    private func sortByStockDepletion(
        _ entries: [MedicinePackage],
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> [MedicinePackage] {
        entries.sorted { lhs, rhs in
            let v1 = stockSortValue(for: lhs, option: option, recurrenceManager: recurrenceManager)
            let v2 = stockSortValue(for: rhs, option: option, recurrenceManager: recurrenceManager)
            if v1 != v2 { return v1 < v2 }
            return lhs.medicine.nome.localizedCaseInsensitiveCompare(rhs.medicine.nome) == .orderedAscending
        }
    }

    private func nextDoseDate(
        for entry: MedicinePackage,
        now: Date,
        recurrenceManager: RecurrenceManager
    ) -> Date? {
        let therapies = therapies(for: entry)
        guard !therapies.isEmpty else { return nil }
        var best: Date?
        for therapy in therapies {
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let startDate = therapy.start_date ?? now
            if let next = recurrenceManager.nextOccurrence(
                rule: rule,
                startDate: startDate,
                after: now,
                doses: therapy.doses as NSSet?
            ) {
                if best == nil || next < best! { best = next }
            }
        }
        return best
    }

    private func stockSortValue(
        for entry: MedicinePackage,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> Double {
        let therapies = therapies(for: entry)
        if !therapies.isEmpty {
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            for therapy in therapies {
                totalLeftover += Double(therapy.leftover())
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            guard totalDailyUsage > 0 else {
                return totalLeftover > 0 ? .greatestFiniteMagnitude : 0
            }
            return max(0, totalLeftover / totalDailyUsage)
        }

        let stockService = StockService(context: viewContext)
        let remaining = stockService.units(for: entry.package)
        return Double(max(0, remaining))
    }

    private func therapies(for entry: MedicinePackage) -> [Therapy] {
        if let set = entry.therapies, !set.isEmpty {
            return Array(set)
        }
        let all = entry.medicine.therapies as? Set<Therapy> ?? []
        return all.filter { $0.package == entry.package }
    }
}
