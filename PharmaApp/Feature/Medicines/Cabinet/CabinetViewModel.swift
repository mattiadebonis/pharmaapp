import SwiftUI
import CoreData

/// ViewModel dedicato al tab "Armadietto".
class CabinetViewModel: ObservableObject {
    // Stato di selezione (solo per il tab Armadietto)
    @Published var selectedEntries: Set<MedicinePackage> = []
    @Published var isSelecting: Bool = false

    let actionService: MedicineActionService

    // MARK: - PharmaCore dependencies
    private let pharmaCoreFactory: PharmaCoreFactory
    private(set) lazy var sectionCalculator = pharmaCoreFactory.makeSectionCalculator()
    private(set) lazy var cabinetSummaryReadModel = pharmaCoreFactory.makeCabinetSummaryReadModel()
    private(set) lazy var doseScheduleReadModel = pharmaCoreFactory.makeDoseScheduleReadModel()
    private(set) lazy var medicineActionUseCase = pharmaCoreFactory.makeMedicineActionUseCase()
    private(set) lazy var medicineRepository: MedicineRepository = pharmaCoreFactory.makeMedicineRepository()
    private(set) lazy var optionRepository: OptionRepository = pharmaCoreFactory.makeOptionRepository()

    init(
        actionService: MedicineActionService = MedicineActionService(),
        pharmaCoreFactory: PharmaCoreFactory = PharmaCoreFactory()
    ) {
        self.actionService = actionService
        self.pharmaCoreFactory = pharmaCoreFactory
    }

    private func snapshotBuilder(for context: NSManagedObjectContext?) -> CoreDataSnapshotBuilder {
        CoreDataSnapshotBuilder(context: context ?? PersistenceController.shared.container.viewContext)
    }

    private func snapshotBuilder(for entries: [MedicinePackage]) -> CoreDataSnapshotBuilder {
        snapshotBuilder(for: entries.first?.managedObjectContext)
    }

    private func snapshotBuilder(for medicines: [Medicine]) -> CoreDataSnapshotBuilder {
        snapshotBuilder(for: medicines.first?.managedObjectContext)
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
        let id: String
        let priority: Int
        let name: String
        let kind: Kind
    }

    struct ShelfViewState {
        let entries: [ShelfEntry]
        let orderedEntriesByCabinetID: [String: [MedicinePackage]]
    }

    struct CabinetRowSnapshot {
        let presentation: MedicineRowView.Snapshot
        let shouldShowPrescription: Bool
    }

    struct SummaryDisplayData {
        let summary: CabinetSummary
        let lines: [String]
        let inlineAction: String
    }

    /// Sezioni ordinate per List (cabinet e medicinali fuori da cabinet).
    func shelfEntries(
        entries: [MedicinePackage],
        option: Option?,
        cabinets: [Cabinet],
        favoriteMedicineIDs: Set<UUID> = []
    ) -> [ShelfEntry] {
        shelfViewState(
            entries: entries,
            option: option,
            cabinets: cabinets,
            favoriteMedicineIDs: favoriteMedicineIDs
        ).entries
    }

    func shelfViewState(
        entries: [MedicinePackage],
        option: Option?,
        cabinets: [Cabinet],
        favoriteMedicineIDs: Set<UUID> = []
    ) -> ShelfViewState {
        let orderedEntries = orderedMedicinePackages(
            entries: entries,
            option: option,
            favoriteMedicineIDs: favoriteMedicineIDs
        )

        var indexMap: [String: Int] = [:]
        for (idx, entry) in orderedEntries.enumerated() {
            indexMap[entryKey(entry)] = idx
        }

        var medicineEntries: [ShelfEntry] = []
        for entry in orderedEntries where entry.cabinet == nil {
            let priority = indexMap[entryKey(entry)] ?? Int.max
            let name = entry.medicine.nome
            medicineEntries.append(ShelfEntry(id: entryKey(entry), priority: priority, name: name, kind: .medicinePackage(entry)))
        }

        let baseIndex = orderedEntries.count
        var cabinetEntries: [ShelfEntry] = []
        for (cabIdx, cabinet) in cabinets.enumerated() {
            let cabinetEntryItems = orderedEntries.filter { cabinetKey($0.cabinet) == cabinetKey(cabinet) }
            let idxs = cabinetEntryItems.compactMap { indexMap[entryKey($0)] }
            let priority = idxs.min() ?? (baseIndex + cabIdx)
            cabinetEntries.append(ShelfEntry(id: cabinetKey(cabinet), priority: priority, name: cabinet.displayName, kind: .cabinet(cabinet)))
        }

        let sorter: (ShelfEntry, ShelfEntry) -> Bool = { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.priority < rhs.priority
        }

        var orderedEntriesByCabinetID: [String: [MedicinePackage]] = [:]
        for entry in orderedEntries {
            if let cabinetID = cabinetKey(entry.cabinet) {
                orderedEntriesByCabinetID[cabinetID, default: []].append(entry)
            }
        }
        for cabinet in cabinets where orderedEntriesByCabinetID[cabinetKey(cabinet)] == nil {
            orderedEntriesByCabinetID[cabinetKey(cabinet)] = []
        }

        return ShelfViewState(
            entries: (medicineEntries + cabinetEntries).sorted(by: sorter),
            orderedEntriesByCabinetID: orderedEntriesByCabinetID
        )
    }

    func sortedEntries(in cabinet: Cabinet, entries: [MedicinePackage], option: Option?) -> [MedicinePackage] {
        let filtered = entries.filter { $0.cabinet?.id == cabinet.id }
        return orderedMedicinePackages(
            entries: filtered,
            option: option,
            favoriteMedicineIDs: []
        )
    }

    func sortedEntries(
        in cabinet: Cabinet,
        entries: [MedicinePackage],
        option: Option?,
        favoriteMedicineIDs: Set<UUID>
    ) -> [MedicinePackage] {
        let filtered = entries.filter { $0.cabinet?.id == cabinet.id }
        return orderedMedicinePackages(
            entries: filtered,
            option: option,
            favoriteMedicineIDs: favoriteMedicineIDs
        )
    }

    func shouldShowPrescriptionAction(for entry: MedicinePackage) -> Bool {
        let builder = snapshotBuilder(for: entry.managedObjectContext)
        let snapshot = builder.makeEntrySnapshot(entry: entry)
        let optionSnapshot = builder.makeOptionSnapshot(option: nil)
        return sectionCalculator.needsPrescriptionBeforePurchase(snapshot, option: optionSnapshot)
    }

    func buildRowSnapshots(
        entries: [MedicinePackage],
        option: Option?,
        now: Date = Date()
    ) -> [String: CabinetRowSnapshot] {
        let recurrenceManager = RecurrenceManager.shared
        let calendar = Calendar.current
        let builder = snapshotBuilder(for: entries)
        let optionSnapshot = builder.makeOptionSnapshot(option: option)

        var snapshots: [String: CabinetRowSnapshot] = [:]
        var medicineLogCache: [String: [Log]] = [:]

        for entry in displayableEntries(from: entries) {
            let medicine = entry.medicine
            let medicineID = medicineKey(medicine)

            // Cache intake logs per medicine
            let intakeLogsToday: [Log]
            if let cached = medicineLogCache[medicineID] {
                intakeLogsToday = cached
            } else {
                let computed = medicine.effectiveIntakeLogs(on: now, calendar: calendar)
                medicineLogCache[medicineID] = computed
                intakeLogsToday = computed
            }

            let filteredLogs = intakeLogsToday.filter { $0.package == entry.package }
            let payload = makeMedicineActiveTherapiesSubtitle(
                medicine: medicine,
                medicinePackage: entry,
                recurrenceManager: recurrenceManager,
                intakeLogsToday: filteredLogs,
                now: now
            )

            // Use PharmaCore for stock status
            let entrySnapshot = builder.makeEntrySnapshot(entry: entry)
            let stockStatus = sectionCalculator.stockStatus(for: entrySnapshot, option: optionSnapshot)
            let autonomyBelowThreshold = (stockStatus == .low || stockStatus == .critical)

            // Use PharmaCore for missed dose detection
            let manualTherapies = entrySnapshot.therapies.filter {
                $0.manualIntakeRegistration || entrySnapshot.manualIntakeRegistration
            }
            let skippedDose: Bool
            if manualTherapies.isEmpty {
                skippedDose = false
            } else {
                let entryIntakeLogs = entrySnapshot.effectiveIntakeLogs(on: now, calendar: calendar)
                skippedDose = doseScheduleReadModel.missedDoseCandidate(
                    for: manualTherapies,
                    intakeLogs: entryIntakeLogs,
                    now: now
                ) != nil
            }

            let presentation = MedicineRowView.Snapshot(
                line1: payload.line1,
                line2: payload.line2,
                therapyLines: payload.therapyLines,
                line1Tone: autonomyBelowThreshold ? .danger : .normal,
                line2Tone: .normal,
                therapyLineTone: skippedDose ? .danger : .normal,
                deadlineIndicator: deadlineIndicator(for: entry)
            )

            // Use PharmaCore for prescription check
            let shouldShowPrescription = sectionCalculator.needsPrescriptionBeforePurchase(
                entrySnapshot,
                option: optionSnapshot
            )

            snapshots[entryKey(entry)] = CabinetRowSnapshot(
                presentation: presentation,
                shouldShowPrescription: shouldShowPrescription
            )
        }

        return snapshots
    }

    func searchEntries(
        query: String,
        entries: [MedicinePackage],
        option: Option?
    ) -> [MedicinePackage] {
        let normalizedQuery = normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let filteredEntries = entries.filter { entry in
            guard entry.medicine.in_cabinet else { return false }

            let medicineName = normalizedSearchText(entry.medicine.nome)
            let principle = normalizedSearchText(entry.medicine.principio_attivo)
            let packageSummary = normalizedSearchText(packageSearchSummary(for: entry.package))

            return medicineName.contains(normalizedQuery)
                || principle.contains(normalizedQuery)
                || packageSummary.contains(normalizedQuery)
        }

        return orderedMedicinePackages(
            entries: filteredEntries,
            option: option,
            favoriteMedicineIDs: []
        )
    }

    /// Computes summary content for the cabinet header and widgets using PharmaCore's CabinetSummaryReadModel.
    func computeSummaryDisplayData(
        medicines: [Medicine],
        option: Option?,
        pharmacy: PharmacyInfo?
    ) -> SummaryDisplayData {
        let input = makeSummaryInput(medicines: medicines, option: option)
        let presentation = cabinetSummaryReadModel.buildPresentation(
            medicines: input.medicineSnapshots,
            option: input.optionSnapshot,
            pharmacy: pharmacy
        )
        let summary = presentation.summary
        let lines = [summary.title, summary.subtitle].filter { !$0.isEmpty }
        return SummaryDisplayData(
            summary: summary,
            lines: lines,
            inlineAction: presentation.inlineAction.text
        )
    }

    func computeSummaryLines(
        medicines: [Medicine],
        option: Option?,
        pharmacy: PharmacyInfo?
    ) -> [String] {
        computeSummaryDisplayData(
            medicines: medicines,
            option: option,
            pharmacy: pharmacy
        ).lines
    }

    /// Computes the structured cabinet summary with priority and state.
    func computeSummary(
        medicines: [Medicine],
        option: Option?,
        pharmacy: PharmacyInfo?
    ) -> CabinetSummary {
        computeSummaryDisplayData(
            medicines: medicines,
            option: option,
            pharmacy: pharmacy
        ).summary
    }

    func computeInlineAction(
        medicines: [Medicine],
        option: Option?,
        pharmacy: PharmacyInfo?
    ) -> String {
        computeSummaryDisplayData(
            medicines: medicines,
            option: option,
            pharmacy: pharmacy
        ).inlineAction
    }

    private func makeSummaryInput(
        medicines: [Medicine],
        option: Option?
    ) -> (medicineSnapshots: [MedicineSnapshot], optionSnapshot: OptionSnapshot?) {
        let builder = snapshotBuilder(for: medicines)
        let medicineSnapshots = medicines.map { medicine in
            builder.makeMedicineSnapshot(
                medicine: medicine,
                logs: Array(medicine.logs ?? [])
            )
        }
        let optionSnapshot = builder.makeOptionSnapshot(option: option)
        return (medicineSnapshots, optionSnapshot)
    }

    // MARK: - Sorting (via PharmaCore SectionCalculator)
    func prioritizeFavoriteMedicines(
        _ entries: [MedicinePackage],
        favoriteMedicineIDs: Set<UUID>
    ) -> [MedicinePackage] {
        guard !favoriteMedicineIDs.isEmpty else { return entries }

        var pinnedEntries: [MedicinePackage] = []
        var regularEntries: [MedicinePackage] = []

        for entry in entries {
            if favoriteMedicineIDs.contains(entry.medicine.id) {
                pinnedEntries.append(entry)
            } else {
                regularEntries.append(entry)
            }
        }

        return pinnedEntries + regularEntries
    }

    private func orderedMedicinePackages(
        entries: [MedicinePackage],
        option: Option?,
        favoriteMedicineIDs: Set<UUID>
    ) -> [MedicinePackage] {
        let visibleEntries = displayableEntries(from: entries)
        let builder = snapshotBuilder(for: visibleEntries)

        // Convert entries to snapshots
        let optionSnapshot = builder.makeOptionSnapshot(option: option)
        var snapshotToEntry: [String: MedicinePackage] = [:]
        var medicineSnapshots: [MedicineSnapshot] = []

        for entry in visibleEntries {
            let snapshot = builder.makeEntrySnapshot(entry: entry)
            snapshotToEntry[snapshot.externalKey] = entry
            medicineSnapshots.append(snapshot)
        }

        // Use PharmaCore priority-based sorting (matches CabinetSummary priority hierarchy)
        let sorted = sectionCalculator.prioritySortedMedicines(for: medicineSnapshots, option: optionSnapshot)

        // Map back to CoreData entities preserving PharmaCore's order
        let orderedEntries = sorted.compactMap { snapshotToEntry[$0.externalKey] }
        return prioritizeFavoriteMedicines(
            orderedEntries,
            favoriteMedicineIDs: favoriteMedicineIDs
        )
    }

    private func normalizedSearchText(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let cleaned = folded.replacingOccurrences(
            of: "[^A-Za-z0-9]",
            with: " ",
            options: .regularExpression
        )
        return cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func packageSearchSummary(for package: Package) -> String {
        var parts: [String] = []
        if package.numero > 0 {
            parts.append("\(package.numero)")
        }
        if !package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(package.tipologia)
        }
        if package.valore > 0 {
            let unit = package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(unit.isEmpty ? "\(package.valore)" : "\(package.valore) \(unit)")
        }
        if !package.volume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(package.volume)
        }
        return parts.joined(separator: " ")
    }

    private struct EntryGroupKey: Hashable {
        let medicineID: String
        let packageID: String
        let cabinetID: String?
    }

    private func displayableEntries(from entries: [MedicinePackage]) -> [MedicinePackage] {
        let active = entries.filter { !$0.isReversed }
        guard !active.isEmpty else { return [] }

        let grouped = Dictionary(grouping: active) { entry in
            EntryGroupKey(
                medicineID: medicineKey(entry.medicine),
                packageID: packageKey(entry.package),
                cabinetID: cabinetKey(entry.cabinet)
            )
        }

        var hiddenPlaceholderIDs = Set<String>()
        for groupEntries in grouped.values {
            let hasPurchasedEntry = groupEntries.contains { $0.isPurchased && !$0.isReversed }
            guard hasPurchasedEntry else { continue }
            for entry in groupEntries where entry.isPlaceholder {
                hiddenPlaceholderIDs.insert(entryKey(entry))
            }
        }

        return active.filter { !hiddenPlaceholderIDs.contains(entryKey($0)) }
    }

    private func deadlineIndicator(for entry: MedicinePackage) -> MedicineRowView.Snapshot.DeadlineIndicator? {
        makeMedicineRowDeadlineIndicator(for: entry.medicine, medicinePackage: entry)
    }

    private func entryKey(_ entry: MedicinePackage) -> String {
        entry.id.uuidString
    }

    private func medicineKey(_ medicine: Medicine) -> String {
        medicine.id.uuidString
    }

    private func packageKey(_ package: Package) -> String {
        package.id.uuidString
    }

    private func cabinetKey(_ cabinet: Cabinet) -> String {
        cabinet.id.uuidString
    }

    private func cabinetKey(_ cabinet: Cabinet?) -> String? {
        guard let cabinet else { return nil }
        return cabinetKey(cabinet)
    }
}
