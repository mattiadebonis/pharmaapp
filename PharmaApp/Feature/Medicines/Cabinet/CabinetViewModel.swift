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

    struct ShelfViewState {
        let entries: [ShelfEntry]
        let orderedEntriesByCabinetID: [NSManagedObjectID: [MedicinePackage]]
    }

    struct CabinetRowSnapshot {
        let presentation: MedicineRowView.Snapshot
        let shouldShowPrescription: Bool
    }

    private struct MedicineLogCache {
        let intakeLogsToday: [Log]
        let hasPrescriptionReceived: Bool
        let hasPrescriptionRequest: Bool
    }

    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    /// Sezioni ordinate per List (cabinet e medicinali fuori da cabinet).
    func shelfEntries(
        entries: [MedicinePackage],
        option: Option?,
        cabinets: [Cabinet]
    ) -> [ShelfEntry] {
        shelfViewState(entries: entries, option: option, cabinets: cabinets).entries
    }

    func shelfViewState(
        entries: [MedicinePackage],
        option: Option?,
        cabinets: [Cabinet]
    ) -> ShelfViewState {
        let orderedEntries = orderedMedicinePackages(
            entries: entries,
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

        var orderedEntriesByCabinetID: [NSManagedObjectID: [MedicinePackage]] = [:]
        for entry in orderedEntries {
            if let cabinetID = entry.cabinet?.objectID {
                orderedEntriesByCabinetID[cabinetID, default: []].append(entry)
            }
        }
        for cabinet in cabinets where orderedEntriesByCabinetID[cabinet.objectID] == nil {
            orderedEntriesByCabinetID[cabinet.objectID] = []
        }

        return ShelfViewState(
            entries: (medicineEntries + cabinetEntries).sorted(by: sorter),
            orderedEntriesByCabinetID: orderedEntriesByCabinetID
        )
    }

    func sortedEntries(in cabinet: Cabinet, entries: [MedicinePackage], option: Option?) -> [MedicinePackage] {
        let filtered = entries.filter { $0.cabinet?.objectID == cabinet.objectID }
        return orderedMedicinePackages(
            entries: filtered,
            option: option
        )
    }

    func shouldShowPrescriptionAction(for entry: MedicinePackage) -> Bool {
        let medicine = entry.medicine
        guard medicine.obbligo_ricetta else { return false }
        if medicine.hasEffectivePrescriptionReceived() { return false }
        if medicine.hasNewPrescritpionRequest() { return false }
        return needsPrescriptionBeforePurchase(
            medicine,
            option: nil,
            recurrenceManager: .shared,
            stockService: StockService(context: viewContext)
        )
    }

    func buildRowSnapshots(
        entries: [MedicinePackage],
        option: Option?,
        now: Date = Date()
    ) -> [NSManagedObjectID: CabinetRowSnapshot] {
        let recurrenceManager = RecurrenceManager.shared
        let calendar = Calendar.current
        let stockService = StockService(context: viewContext)

        var snapshots: [NSManagedObjectID: CabinetRowSnapshot] = [:]
        var medicineCache: [NSManagedObjectID: MedicineLogCache] = [:]

        for entry in entries {
            let medicine = entry.medicine
            let medicineID = medicine.objectID
            let cached: MedicineLogCache
            if let existing = medicineCache[medicineID] {
                cached = existing
            } else {
                let computed = MedicineLogCache(
                    intakeLogsToday: medicine.effectiveIntakeLogs(on: now, calendar: calendar),
                    hasPrescriptionReceived: medicine.hasEffectivePrescriptionReceived(),
                    hasPrescriptionRequest: medicine.hasNewPrescritpionRequest()
                )
                medicineCache[medicineID] = computed
                cached = computed
            }

            let intakeLogsToday = cached.intakeLogsToday.filter { $0.package == entry.package }
            let payload = makeMedicineActiveTherapiesSubtitle(
                medicine: medicine,
                medicinePackage: entry,
                recurrenceManager: recurrenceManager,
                intakeLogsToday: intakeLogsToday,
                now: now
            )

            let entryTherapies = therapies(for: entry)
            let autonomyBelowThreshold = isAutonomyBelowThreshold(
                entry: entry,
                therapies: entryTherapies,
                option: option,
                recurrenceManager: recurrenceManager,
                stockService: stockService
            )
            let skippedDose = hasSkippedDose(
                entry: entry,
                therapies: entryTherapies,
                intakeLogsToday: intakeLogsToday,
                now: now,
                calendar: calendar,
                recurrenceManager: recurrenceManager
            )

            let presentation = MedicineRowView.Snapshot(
                line1: payload.line1,
                line2: payload.line2,
                therapyLines: payload.therapyLines,
                line1Tone: autonomyBelowThreshold ? .danger : .normal,
                line2Tone: .normal,
                therapyLineTone: skippedDose ? .danger : .normal,
                deadlineIndicator: deadlineIndicator(for: medicine)
            )

            let shouldShowPrescription = shouldShowPrescriptionAction(
                for: entry,
                cachedState: cached,
                option: option,
                recurrenceManager: recurrenceManager,
                stockService: stockService
            )

            snapshots[entry.objectID] = CabinetRowSnapshot(
                presentation: presentation,
                shouldShowPrescription: shouldShowPrescription
            )
        }

        return snapshots
    }

    // MARK: - Sorting
    private func orderedMedicinePackages(
        entries: [MedicinePackage],
        option: Option?
    ) -> [MedicinePackage] {
        let sections = computeSections(for: entries, option: option)
        return sections.purchase + sections.oggi + sections.ok
    }

    private func therapies(for entry: MedicinePackage) -> [Therapy] {
        if let set = entry.therapies, !set.isEmpty {
            return Array(set)
        }
        let all = entry.medicine.therapies ?? []
        return all.filter { $0.package == entry.package }
    }

    private func shouldShowPrescriptionAction(
        for entry: MedicinePackage,
        cachedState: MedicineLogCache,
        option: Option?,
        recurrenceManager: RecurrenceManager,
        stockService: StockService
    ) -> Bool {
        let medicine = entry.medicine
        guard medicine.obbligo_ricetta else { return false }
        if cachedState.hasPrescriptionReceived { return false }
        if cachedState.hasPrescriptionRequest { return false }
        return needsPrescriptionBeforePurchase(
            medicine,
            option: option,
            recurrenceManager: recurrenceManager,
            stockService: stockService
        )
    }

    private func needsPrescriptionBeforePurchase(
        _ medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager,
        stockService: StockService
    ) -> Bool {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalLeft <= 0 { return true }
            guard dailyUsage > 0 else { return false }
            let days = totalLeft / dailyUsage
            let threshold = Double(medicine.stockThreshold(option: option))
            return days < threshold
        }

        let remaining = stockService.unitsReadOnly(for: medicine)
        return remaining <= medicine.stockThreshold(option: option)
    }

    private func isAutonomyBelowThreshold(
        entry: MedicinePackage,
        therapies: [Therapy],
        option: Option?,
        recurrenceManager: RecurrenceManager,
        stockService: StockService
    ) -> Bool {
        let threshold = entry.medicine.stockThreshold(option: option)

        if !therapies.isEmpty {
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            for therapy in therapies {
                totalLeftover += Double(therapy.leftover())
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            guard totalDailyUsage > 0 else { return false }
            let days = Int(totalLeftover / totalDailyUsage)
            return days < threshold
        }

        let remainingUnits = stockService.unitsReadOnly(for: entry.package)
        return remainingUnits < threshold
    }

    private func hasSkippedDose(
        entry: MedicinePackage,
        therapies: [Therapy],
        intakeLogsToday: [Log],
        now: Date,
        calendar: Calendar,
        recurrenceManager: RecurrenceManager
    ) -> Bool {
        let manualTherapies = therapies.filter { $0.manual_intake_registration }
        guard !manualTherapies.isEmpty else { return false }
        let plannedTimes = scheduledTimesToday(
            for: manualTherapies,
            now: now,
            calendar: calendar,
            recurrenceManager: recurrenceManager
        )
        guard !plannedTimes.isEmpty else { return false }

        let takenCount = intakeLogsToday.count
        let pendingTimes = plannedTimes.dropFirst(min(takenCount, plannedTimes.count))
        return pendingTimes.first(where: { $0 <= now }) != nil
    }

    private func scheduledTimesToday(
        for therapies: [Therapy],
        now: Date,
        calendar: Calendar,
        recurrenceManager: RecurrenceManager
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var planned: [Date] = []

        for therapy in therapies {
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? today
            let doses = (therapy.doses ?? []).sorted { $0.time < $1.time }
            let perDay = max(1, doses.count)
            let allowed = recurrenceManager.allowedEvents(
                on: today,
                rule: rule,
                startDate: start,
                dosesPerDay: perDay,
                calendar: calendar
            )
            guard allowed > 0 else { continue }
            guard !doses.isEmpty else { continue }

            let limitedDoses = doses.prefix(min(allowed, doses.count))
            for dose in limitedDoses {
                if let combined = combine(day: today, withTime: dose.time, calendar: calendar) {
                    planned.append(combined)
                }
            }
        }

        return planned.sorted()
    }

    private func combine(day: Date, withTime time: Date, calendar: Calendar) -> Date? {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)

        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second
        return calendar.date(from: merged)
    }

    private func deadlineIndicator(for medicine: Medicine) -> MedicineRowView.Snapshot.DeadlineIndicator? {
        makeMedicineRowDeadlineIndicator(for: medicine)
    }
}
