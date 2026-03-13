import SwiftUI

/// ViewModel dedicato al tab "Armadietto".
class CabinetViewModel: ObservableObject {
    // Stato di selezione (solo per il tab Armadietto)
    @Published var selectedEntryIDs: Set<UUID> = []
    @Published var isSelecting: Bool = false

    // MARK: - PharmaCore dependencies
    private let pharmaCoreFactory: PharmaCoreFactory
    private(set) lazy var sectionCalculator = pharmaCoreFactory.makeSectionCalculator()
    private(set) lazy var cabinetSummaryReadModel = pharmaCoreFactory.makeCabinetSummaryReadModel()
    private(set) lazy var doseScheduleReadModel = pharmaCoreFactory.makeDoseScheduleReadModel()
    private(set) lazy var medicineActionUseCase = pharmaCoreFactory.makeMedicineActionUseCase()
    private(set) lazy var medicineRepository: MedicineRepository = pharmaCoreFactory.makeMedicineRepository()
    private(set) lazy var optionRepository: OptionRepository = pharmaCoreFactory.makeOptionRepository()

    init(
        pharmaCoreFactory: PharmaCoreFactory = PharmaCoreFactory()
    ) {
        self.pharmaCoreFactory = pharmaCoreFactory
    }

    private func snapshotBuilder(for entries: [MedicinePackage]) -> CoreDataSnapshotBuilder? {
        guard let context = entries.first?.managedObjectContext else { return nil }
        return CoreDataSnapshotBuilder(context: context)
    }

    private func snapshotBuilder(for medicines: [Medicine]) -> CoreDataSnapshotBuilder? {
        guard let context = medicines.first?.managedObjectContext else { return nil }
        return CoreDataSnapshotBuilder(context: context)
    }

    private func makeOptionSnapshot(option: Option?) -> OptionSnapshot? {
        guard let option else { return nil }
        return OptionSnapshot(
            manualIntakeRegistration: option.manual_intake_registration,
            dayThresholdStocksAlarm: Int(option.day_threeshold_stocks_alarm)
        )
    }

    // MARK: - Selection
    func enterSelectionMode(with entryId: UUID) {
        isSelecting = true
        selectedEntryIDs.insert(entryId)
    }

    func toggleSelection(for entryId: UUID) {
        if selectedEntryIDs.contains(entryId) {
            selectedEntryIDs.remove(entryId)
            if selectedEntryIDs.isEmpty {
                isSelecting = false
            }
        } else {
            selectedEntryIDs.insert(entryId)
        }
    }

    func cancelSelection() {
        selectedEntryIDs.removeAll()
        isSelecting = false
    }

    func clearSelection() {
        DispatchQueue.main.async {
            self.selectedEntryIDs.removeAll()
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

    struct SummaryKPI {
        enum StockStatusTone: Equatable {
            case neutral
            case success
            case warning
            case critical
        }

        let coveredCount: Int
        let totalCount: Int
        let valueText: String
        let labelText: String
        let inlineText: String
        let stockStatusText: String
        let stockStatusDetailText: String?
        let stockStatusTone: StockStatusTone
        let refillCount: Int
        let nextRefillInDays: Int?

        static let empty = SummaryKPI(
            coveredCount: 0,
            totalCount: 0,
            valueText: "0 su 0",
            labelText: "farmaci coperti",
            inlineText: "Scorte 0/0",
            stockStatusText: "Vuoto",
            stockStatusDetailText: nil,
            stockStatusTone: .neutral,
            refillCount: 0,
            nextRefillInDays: nil
        )

        var coverageFraction: Double {
            guard totalCount > 0 else { return 0 }
            return Double(coveredCount) / Double(totalCount)
        }

        var uncoveredCount: Int {
            max(0, totalCount - coveredCount)
        }
    }

    struct SummaryDisplayData {
        let summary: CabinetSummary
        let kpi: SummaryKPI
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
        guard let context = entry.managedObjectContext else { return false }
        let builder = CoreDataSnapshotBuilder(context: context)
        let snapshot = builder.makeEntrySnapshot(entry: entry)
        let optionSnapshot = makeOptionSnapshot(option: nil)
        return sectionCalculator.needsPrescriptionBeforePurchase(snapshot, option: optionSnapshot)
    }

    func buildRowSnapshots(
        entries: [MedicinePackage],
        option: Option?,
        now: Date = Date()
    ) -> [String: CabinetRowSnapshot] {
        guard !entries.isEmpty else { return [:] }
        let recurrenceManager = RecurrenceManager.shared
        let calendar = Calendar.current
        guard let builder = snapshotBuilder(for: entries) else { return [:] }
        let optionSnapshot = makeOptionSnapshot(option: option)

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
                line2Tone: stockStatus == .critical ? .danger : .normal,
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
            let medicineLabels = normalizedSearchText(entry.medicine.searchableLabelsText)
            let principle = normalizedSearchText(entry.medicine.principio_attivo)
            let packageSummary = normalizedSearchText(packageSearchSummary(for: entry.package))

            return medicineName.contains(normalizedQuery)
                || medicineLabels.contains(normalizedQuery)
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
        let kpi = computeSummaryKPI(
            medicines: input.medicineSnapshots,
            option: input.optionSnapshot
        )
        let summary = presentation.summary
        let lines: [String]

        if isRefillPriority(summary.priority) {
            let pharmacyLine = summary.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if pharmacyLine.isEmpty {
                lines = [kpi.valueText, kpi.labelText]
            } else {
                lines = [kpi.valueText, kpi.labelText, pharmacyLine]
            }
        } else {
            lines = [kpi.valueText, kpi.labelText]
        }

        return SummaryDisplayData(
            summary: summary,
            kpi: kpi,
            lines: lines,
            inlineAction: kpi.inlineText
        )
    }

    private func computeSummaryKPI(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?
    ) -> SummaryKPI {
        let total = medicines.count
        var covered = 0
        var criticalCount = 0
        var lowCount = 0
        var unknownCount = 0
        var refillCount = 0
        var refillDays: [Int] = []

        for medicine in medicines {
            let status = sectionCalculator.stockStatus(for: medicine, option: option)
            if status == .ok {
                covered += 1
            }
            switch status {
            case .critical:
                criticalCount += 1
                refillCount += 1
                if let days = refillAutonomyDays(for: medicine) {
                    refillDays.append(max(0, days))
                }
            case .low:
                lowCount += 1
                refillCount += 1
                if let days = refillAutonomyDays(for: medicine) {
                    refillDays.append(max(0, days))
                }
            case .unknown:
                unknownCount += 1
            case .ok:
                break
            }
        }

        let statusValueText: String
        let statusTone: SummaryKPI.StockStatusTone
        if total == 0 {
            statusValueText = "Vuoto"
            statusTone = .neutral
        } else if criticalCount > 0 {
            statusValueText = "Critico"
            statusTone = .critical
        } else if lowCount > 0 {
            statusValueText = "Attenzione"
            statusTone = .warning
        } else if unknownCount > 0 {
            statusValueText = "Da verificare"
            statusTone = .warning
        } else {
            statusValueText = "Sotto controllo"
            statusTone = .success
        }

        let nextRefillInDays = refillDays.min()
        let statusDetailText: String?
        if refillCount > 0 {
            let refillText = refillCount == 1
                ? "1 farmaco da rifornire"
                : "\(refillCount) farmaci da rifornire"
            let nextText: String
            if let nextRefillInDays {
                switch nextRefillInDays {
                case ...0:
                    nextText = "prossimo oggi"
                case 1:
                    nextText = "prossimo domani"
                default:
                    nextText = "prossimo tra \(nextRefillInDays) giorni"
                }
            } else {
                nextText = "prossimo da verificare"
            }
            statusDetailText = "\(refillText) · \(nextText)"
        } else {
            statusDetailText = nil
        }

        return SummaryKPI(
            coveredCount: covered,
            totalCount: total,
            valueText: "\(covered) su \(total)",
            labelText: "farmaci coperti",
            inlineText: "Scorte \(covered)/\(total)",
            stockStatusText: statusValueText,
            stockStatusDetailText: statusDetailText,
            stockStatusTone: statusTone,
            refillCount: refillCount,
            nextRefillInDays: nextRefillInDays
        )
    }

    private func refillAutonomyDays(for medicine: MedicineSnapshot) -> Int? {
        guard !medicine.therapies.isEmpty else { return nil }

        var totalLeftover: Double = 0
        var totalDailyUsage: Double = 0
        let recurrenceService = pharmaCoreFactory.makeRecurrenceService()

        for therapy in medicine.therapies {
            totalLeftover += Double(therapy.leftoverUnits)
            totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
        }

        if totalLeftover <= 0 {
            return 0
        }
        guard totalDailyUsage > 0 else {
            return nil
        }
        return max(0, Int(floor(totalLeftover / totalDailyUsage)))
    }

    private func isRefillPriority(_ priority: CabinetSummaryPriority) -> Bool {
        switch priority {
        case .refillBeforeNextDose, .refillWithinToday, .refillSoon:
            return true
        default:
            return false
        }
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
        let optionSnapshot = makeOptionSnapshot(option: option)
        guard !medicines.isEmpty, let builder = snapshotBuilder(for: medicines) else {
            return ([], optionSnapshot)
        }
        let medicineSnapshots = medicines.map { medicine in
            builder.makeMedicineSnapshot(
                medicine: medicine,
                logs: Array(medicine.logs ?? [])
            )
        }
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
        let _ = option
        let visibleEntries = displayableEntries(from: entries)
        guard !visibleEntries.isEmpty else { return [] }

        let context = visibleEntries.first?.managedObjectContext
        let recurrenceManager = context.map { RecurrenceManager(context: $0) } ?? RecurrenceManager.shared
        let stockService = context.map { StockService(context: $0) }

        let orderedEntries = visibleEntries.sorted { lhs, rhs in
            let lhsMetric = remainingDaysSortMetric(
                for: lhs,
                recurrenceManager: recurrenceManager,
                stockService: stockService
            )
            let rhsMetric = remainingDaysSortMetric(
                for: rhs,
                recurrenceManager: recurrenceManager,
                stockService: stockService
            )

            if lhsMetric.bucket != rhsMetric.bucket {
                return lhsMetric.bucket < rhsMetric.bucket
            }
            if lhsMetric.value != rhsMetric.value {
                return lhsMetric.value < rhsMetric.value
            }
            let nameCompare = lhs.medicine.nome.localizedCaseInsensitiveCompare(rhs.medicine.nome)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return prioritizeFavoriteMedicines(
            orderedEntries,
            favoriteMedicineIDs: favoriteMedicineIDs
        )
    }

    private func remainingDaysSortMetric(
        for entry: MedicinePackage,
        recurrenceManager: RecurrenceManager,
        stockService: StockService?
    ) -> (bucket: Int, value: Double) {
        let therapies = therapies(for: entry)
        let units = max(0, stockService?.unitsReadOnly(for: entry.package) ?? 0)

        if !therapies.isEmpty {
            let dailyUsage = therapies.reduce(0.0) { partial, therapy in
                partial + therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if dailyUsage > 0 {
                let days = Double(units) / dailyUsage
                return (bucket: 0, value: max(0, days))
            }
        }

        return (bucket: 1, value: Double(units))
    }

    private func therapies(for entry: MedicinePackage) -> Set<Therapy> {
        let linked = (entry.therapies ?? []).filter {
            $0.medicine.id == entry.medicine.id
                && $0.package.id == entry.package.id
        }
        let fallback = (entry.medicine.therapies ?? []).filter {
            $0.package.id == entry.package.id
        }
        return Set(linked).union(fallback)
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

        var visibleEntries: [MedicinePackage] = []
        visibleEntries.reserveCapacity(grouped.count)

        for groupEntries in grouped.values {
            let candidates = groupEntries.filter { !hiddenPlaceholderIDs.contains(entryKey($0)) }
            guard !candidates.isEmpty else { continue }
            visibleEntries.append(preferredEntry(from: candidates))
        }

        return visibleEntries
    }

    private func preferredEntry(from entries: [MedicinePackage]) -> MedicinePackage {
        entries.max { lhs, rhs in
            // Prefer purchased entries over placeholders when both are still visible.
            if lhs.isPurchased != rhs.isPurchased {
                return !lhs.isPurchased && rhs.isPurchased
            }

            // Keep the most recent entry for the same medicine/package/cabinet tuple.
            let lhsCreated = lhs.created_at ?? .distantPast
            let rhsCreated = rhs.created_at ?? .distantPast
            if lhsCreated != rhsCreated {
                return lhsCreated < rhsCreated
            }

            return lhs.id.uuidString < rhs.id.uuidString
        } ?? entries[0]
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
