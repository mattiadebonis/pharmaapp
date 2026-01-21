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
    @Published var selectedMedicines: Set<Medicine> = []
    @Published var isSelecting: Bool = false
    @Published var sortOrder: CabinetSortOrder = .byType

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
        let orderedMeds = orderedMedicines(
            medicines: medicines,
            logs: logs,
            option: option
        )

        var indexMap: [NSManagedObjectID: Int] = [:]
        for (idx, med) in orderedMeds.enumerated() {
            indexMap[med.objectID] = idx
        }

        var medicineEntries: [ShelfEntry] = []
        for med in orderedMeds where med.cabinet == nil {
            let priority = indexMap[med.objectID] ?? Int.max
            medicineEntries.append(ShelfEntry(id: med.objectID, priority: priority, name: med.nome, kind: .medicine(med)))
        }

        let baseIndex = orderedMeds.count
        var cabinetEntries: [ShelfEntry] = []
        for (cabIdx, cabinet) in cabinets.enumerated() {
            let meds = cabinet.medicines
            let idxs = meds.compactMap { indexMap[$0.objectID] }
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

    func sortedMedicines(in cabinet: Cabinet, logs: [Log], option: Option?) -> [Medicine] {
        orderedMedicines(
            medicines: Array(cabinet.medicines),
            logs: logs,
            option: option
        )
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

    // MARK: - Sorting
    private func orderedMedicines(
        medicines: [Medicine],
        logs: [Log],
        option: Option?
    ) -> [Medicine] {
        switch sortOrder {
        case .relevance, .byType:
            let sections = computeSections(for: medicines, logs: logs, option: option)
            return sections.purchase + sections.oggi + sections.ok
        case .nextDose:
            let recurrenceManager = RecurrenceManager(context: viewContext)
            let now = Date()
            return sortByNextDose(
                medicines,
                now: now,
                recurrenceManager: recurrenceManager
            )
        case .stockDepletion:
            let recurrenceManager = RecurrenceManager(context: viewContext)
            return sortByStockDepletion(
                medicines,
                option: option,
                recurrenceManager: recurrenceManager
            )
        }
    }

    private func sortByNextDose(
        _ medicines: [Medicine],
        now: Date,
        recurrenceManager: RecurrenceManager
    ) -> [Medicine] {
        medicines.sorted { lhs, rhs in
            let d1 = nextDoseDate(for: lhs, now: now, recurrenceManager: recurrenceManager) ?? .distantFuture
            let d2 = nextDoseDate(for: rhs, now: now, recurrenceManager: recurrenceManager) ?? .distantFuture
            if d1 != d2 { return d1 < d2 }
            return lhs.nome.localizedCaseInsensitiveCompare(rhs.nome) == .orderedAscending
        }
    }

    private func sortByStockDepletion(
        _ medicines: [Medicine],
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> [Medicine] {
        medicines.sorted { lhs, rhs in
            let v1 = stockSortValue(for: lhs, option: option, recurrenceManager: recurrenceManager)
            let v2 = stockSortValue(for: rhs, option: option, recurrenceManager: recurrenceManager)
            if v1 != v2 { return v1 < v2 }
            return lhs.nome.localizedCaseInsensitiveCompare(rhs.nome) == .orderedAscending
        }
    }

    private func nextDoseDate(
        for medicine: Medicine,
        now: Date,
        recurrenceManager: RecurrenceManager
    ) -> Date? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
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
        for medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> Double {
        if let therapies = medicine.therapies, !therapies.isEmpty {
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

        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            return Double(max(0, remaining))
        }
        return .greatestFiniteMagnitude
    }
}
