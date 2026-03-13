import SwiftUI
import WidgetKit

/// Vista dedicata al tab "Armadietto" (ex ramo medicines di FeedView)
struct CabinetView: View {
    private struct EntrySelection: Identifiable {
        let id: UUID
    }

    private enum CustomFilterEditorMode: Identifiable {
        case create
        case edit(CabinetCustomFilterRecord)

        var id: String {
            switch self {
            case .create:
                return "create"
            case .edit(let filter):
                return "edit-\(filter.id.uuidString)"
            }
        }
    }

    private struct ShelfViewState {
        let pinnedMedicineEntries: [CabinetViewModel.ShelfEntry]
        let cabinetEntries: [CabinetViewModel.ShelfEntry]
        let otherMedicineEntries: [CabinetViewModel.ShelfEntry]
        let orderedEntriesByCabinetID: [String: [MedicinePackage]]

        static let empty = ShelfViewState(
            pinnedMedicineEntries: [],
            cabinetEntries: [],
            otherMedicineEntries: [],
            orderedEntriesByCabinetID: [:]
        )
    }

    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let emptyStateImageHeight: CGFloat = 320
        static let emptyStateImageScale: CGFloat = 2
        static let emptyStateImageHorizontalOffset: CGFloat = 12
        static let emptyStateImageTopPadding: CGFloat = -60
        static let emptyStateImageBottomPadding: CGFloat = 24
        static let emptyStateOverlayLeadingPadding: CGFloat = 10
        static let emptyStateOverlayTopPadding: CGFloat = 52
        static let emptyStateOverlayTextMaxWidth: CGFloat = 320
        static let emptyStateBottomTextTopPadding: CGFloat = 12
        static let emptyStateBottomTextHorizontalInset: CGFloat = 14
    }

    private enum StockFilterIndicator: Equatable {
        case ok
        case protected
        case warning
        case critical

        var systemImage: String {
            "shield.fill"
        }

        var color: Color {
            switch self {
            case .ok:
                return .green
            case .protected, .warning:
                return .orange
            case .critical:
                return .red
            }
        }
    }

    private struct FilterChipPresentation {
        let count: Int
        let indicator: StockFilterIndicator
    }

    private struct CustomFilterEditorSheet: View {
        let mode: CustomFilterEditorMode
        let previewResolver: (String) -> FilterChipPresentation?
        let parser: CabinetCustomFilterQueryParser
        let onSave: (String, String) -> Void

        @Environment(\.dismiss) private var dismiss
        @State private var name: String
        @State private var query: String
        @State private var validationError: String?
        @State private var preview: FilterChipPresentation?

        init(
            mode: CustomFilterEditorMode,
            previewResolver: @escaping (String) -> FilterChipPresentation?,
            parser: CabinetCustomFilterQueryParser,
            onSave: @escaping (String, String) -> Void
        ) {
            self.mode = mode
            self.previewResolver = previewResolver
            self.parser = parser
            self.onSave = onSave

            switch mode {
            case .create:
                _name = State(initialValue: "")
                _query = State(initialValue: "")
            case .edit(let filter):
                _name = State(initialValue: filter.name)
                _query = State(initialValue: filter.query)
            }
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section("Nome filtro") {
                        TextField("Es. Scorte casa", text: $name)
                            .textInputAutocapitalization(.words)
                        if trimmedName.isEmpty {
                            Text("Nome obbligatorio.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    Section("Query") {
                        TextField("Es. stock:low AND NOT cabinet:\"Ufficio\"", text: $query, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(2...5)
                        Text("Campi: name, label, stock, therapy, rx, cabinet, deadline. Supporta AND, OR, NOT e parentesi.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let validationError {
                            Text(validationError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    if let preview {
                        Section("Anteprima") {
                            HStack(spacing: 8) {
                                Text("\(preview.count) farmaci")
                                Spacer()
                                Image(systemName: preview.indicator.systemImage)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(preview.indicator.color)
                            }
                        }
                    }
                }
                .navigationTitle(modeTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") {
                            onSave(trimmedName, trimmedQuery)
                            dismiss()
                        }
                        .disabled(isSaveDisabled)
                    }
                }
                .onAppear {
                    recomputeValidationAndPreview()
                }
                .onChange(of: query) { _ in
                    recomputeValidationAndPreview()
                }
            }
        }

        private var modeTitle: String {
            switch mode {
            case .create:
                return "Nuovo filtro"
            case .edit:
                return "Modifica filtro"
            }
        }

        private var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedQuery: String {
            query.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var isSaveDisabled: Bool {
            trimmedName.isEmpty || trimmedQuery.isEmpty || validationError != nil
        }

        private func recomputeValidationAndPreview() {
            let query = trimmedQuery
            guard !query.isEmpty else {
                validationError = "Query obbligatoria."
                preview = nil
                return
            }

            do {
                _ = try parser.parse(query)
                validationError = nil
                preview = previewResolver(query)
            } catch let error as CabinetCustomFilterLanguageError {
                validationError = error.errorDescription
                preview = nil
            } catch {
                validationError = "Query non valida."
                preview = nil
            }
        }
    }

    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appDataStore: AppDataStore
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @StateObject private var viewModel = CabinetViewModel()
    @StateObject private var locationVM = LocationSearchViewModel()

    @State private var medicinePackages: [MedicinePackage] = []
    @State private var options: [Option] = []
    @State private var cabinets: [Cabinet] = []
    @State private var customFilters: [CabinetCustomFilterRecord] = []

    @State private var activeFilter: CabinetFilter?
    @State private var activeCabinetID: String?
    @State private var entryToMoveSelection: EntrySelection?
    @State private var isNewCabinetPresented = false
    @State private var newCabinetName = ""
    @State private var isCatalogAddPresented = false
    @State private var shouldAutoStartCatalogScan = false
    @State private var isProfilePresented = false
    @State private var customFilterEditorMode: CustomFilterEditorMode?
    @State private var pendingCustomFilterDeletion: CabinetCustomFilterRecord?
    @State private var selectedEntrySelection: EntrySelection?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.75)
    @State private var cachedSummaryLines: [String] = [
        "0 su 0",
        "farmaci coperti"
    ]
    @State private var cachedInlineAction: String = "Scorte 0/0"
    @State private var cachedMedicineStockStatuses: [UUID: StockStatus] = [:]
    @State private var cachedFilterChipPresentations: [String: FilterChipPresentation] = [:]
    @State private var cachedShelfState: ShelfViewState = .empty
    @State private var rowSnapshotsByEntryID: [String: CabinetViewModel.CabinetRowSnapshot] = [:]
    @State private var syncWorkItem: DispatchWorkItem?

    private let customFilterParser = CabinetCustomFilterQueryParser()
    private let customFilterEvaluator = CabinetCustomFilterEvaluator()

    var body: some View {
        cabinetRootView
    }

    private var cabinetRootView: some View {
        cabinetListWithNavigation
    }

    private var cabinetListWithNavigation: some View {
        cabinetListWithNewCabinetSheet
            .navigationTitle("Armadietto")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isProfilePresented = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.headline)
                    }
                    .accessibilityLabel("Profilo")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shouldAutoStartCatalogScan = false
                        isCatalogAddPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                    .accessibilityLabel("Aggiungi farmaco")
                }
            }
            .task {
                locationVM.ensureStarted()
                reloadFetchedState()
                recomputeAllCachedState()
                handlePendingRoute(appRouter.pendingRoute)
                for await _ in appDataStore.provider.observe(
                    scopes: [.medicines, .therapies, .logs, .stocks, .cabinets, .options, .customFilters]
                ) {
                    reloadFetchedState()
                    recomputeAllCachedState()
                }
            }
            .onChange(of: favoritesStore.favoriteMedicineIDs) { _ in
                recomputeShelfState()
            }
            .onChange(of: favoritesStore.favoriteCabinetIDs) { _ in
                recomputeShelfState()
            }
            .onChange(of: locationVM.pinItem?.title) { _ in
                recomputeSummaryLines()
                syncSummaryToWidgetDebounced()
            }
            .onChange(of: locationVM.isLikelyOpen) { _ in
                recomputeSummaryLines()
                syncSummaryToWidgetDebounced()
            }
            .onChange(of: locationVM.distanceString) { _ in
                recomputeSummaryLines()
                syncSummaryToWidgetDebounced()
            }
            .onChange(of: locationVM.walkingRouteMinutes) { _ in
                recomputeSummaryLines()
                syncSummaryToWidgetDebounced()
            }
            .onChange(of: locationVM.drivingRouteMinutes) { _ in
                recomputeSummaryLines()
                syncSummaryToWidgetDebounced()
            }
            .onChange(of: appRouter.pendingRoute) { route in
                handlePendingRoute(route)
            }
    }

    private func recomputeAllCachedState() {
        recomputeSummaryLines()
        recomputeFilterChipPresentations()
        recomputeShelfState()
        syncSummaryToWidgetDebounced()
    }

    private func reloadFetchedState() {
        do {
            let snapshot = try appDataStore.provider.medicines.fetchCabinetSnapshot()
            medicinePackages = snapshot.medicinePackages
            options = snapshot.options
            cabinets = snapshot.cabinets
            customFilters = snapshot.customFilters.sorted { lhs, rhs in
                if lhs.position == rhs.position {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.position < rhs.position
            }
        } catch {
            medicinePackages = []
            options = []
            cabinets = []
            customFilters = []
        }

        if let activeFilter,
           !availableFilters.contains(where: { $0.id == activeFilter.id }) {
            self.activeFilter = nil
        }
    }

    private func recomputeSummaryLines() {
        let displayData = computeSummaryDisplayData()
        cachedSummaryLines = displayData.lines
        cachedInlineAction = displayData.inlineAction
    }

    private func handlePendingRoute(_ route: AppRoute?) {
        guard let route else { return }

        switch route {
        case .addMedicine:
            shouldAutoStartCatalogScan = false
            isCatalogAddPresented = true
            appRouter.markRouteHandled(.addMedicine)
        case .scan:
            shouldAutoStartCatalogScan = true
            isCatalogAddPresented = true
            appRouter.markRouteHandled(.scan)
        case .pharmacy, .codiceFiscaleFullscreen, .profile:
            break
        }
    }

    private func syncSummaryToWidgetDebounced() {
        syncWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            CabinetSummarySharedStore.write(cachedSummaryLines, inlineAction: cachedInlineAction)
            WidgetCenter.shared.reloadTimelines(ofKind: "CabinetSummaryWidget")
        }
        syncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private var cabinetListWithNewCabinetSheet: some View {
        cabinetListWithDetailSheet
            .sheet(isPresented: $isNewCabinetPresented, onDismiss: { newCabinetName = "" }) {
                newCabinetSheet
            }
            .sheet(isPresented: $isCatalogAddPresented, onDismiss: {
                shouldAutoStartCatalogScan = false
            }) {
                NavigationStack {
                    CatalogAddMedicineView(autoStartScan: shouldAutoStartCatalogScan)
                }
            }
            .sheet(isPresented: $isProfilePresented) {
                NavigationStack {
                    ProfileView()
                }
            }
            .sheet(item: $customFilterEditorMode) { mode in
                CustomFilterEditorSheet(
                    mode: mode,
                    previewResolver: previewPresentation(for:),
                    parser: customFilterParser
                ) { name, query in
                    switch mode {
                    case .create:
                        createCustomFilter(name: name, query: query)
                    case .edit(let filter):
                        updateCustomFilter(filterID: filter.id, name: name, query: query)
                    }
                }
            }
            .confirmationDialog(
                "Eliminare questo filtro?",
                isPresented: Binding(
                    get: { pendingCustomFilterDeletion != nil },
                    set: { newValue in
                        if !newValue {
                            pendingCustomFilterDeletion = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) {
                    guard let filter = pendingCustomFilterDeletion else { return }
                    deleteCustomFilter(filterID: filter.id)
                }
                Button("Annulla", role: .cancel) {
                    pendingCustomFilterDeletion = nil
                }
            } message: {
                Text(pendingCustomFilterDeletion?.name ?? "")
            }
    }

    private var cabinetListWithDetailSheet: some View {
        cabinetListStyled
            .sheet(isPresented: Binding(
                get: {
                    guard let selection = selectedEntrySelection else { return false }
                    return currentEntry(id: selection.id) != nil
                },
                set: { newValue in if !newValue { selectedEntrySelection = nil } }
            )) {
                if let selection = selectedEntrySelection,
                   let entry = currentEntry(id: selection.id) {
                    MedicineDetailView(
                        medicine: entry.medicine,
                        package: entry.package,
                        medicinePackage: entry
                    )
                    .presentationDetents([.fraction(0.75), .large], selection: $detailSheetDetent)
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $entryToMoveSelection) { selection in
                if let entry = currentEntry(id: selection.id) {
                    MoveToCabinetSheet(
                        entry: entry,
                        cabinets: Array(cabinets),
                        onSelect: { cabinet in
                            do {
                                try appDataStore.provider.medicines.moveEntry(
                                    entryId: entry.id,
                                    toCabinet: cabinet?.id
                                )
                            } catch {
                                // Keep current behavior: ignore move failures and stay on sheet flow.
                            }
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
            }
    }

    private var cabinetListStyled: some View {
        cabinetListView
            .listSectionSeparator(.hidden)
            .listSectionSpacingIfAvailable(4)
            .listRowSpacing(0)
            .listStyle(.plain)
            .scrollDisabled(isShelfEmpty(cachedShelfState))
            .scrollIndicators(.hidden)
    }

    private func computeSummaryDisplayData() -> CabinetViewModel.SummaryDisplayData {
        viewModel.computeSummaryDisplayData(
            medicines: uniqueMedicines,
            option: options.first,
            pharmacy: summaryPharmacyInfo
        )
    }

    private var summaryPharmacyInfo: PharmacyInfo? {
        let normalizedName = locationVM.pinItem?.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (normalizedName?.isEmpty == false) ? normalizedName : nil
        let normalizedDistance = (pharmacyRouteSummaryText ?? locationVM.distanceString)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let distance = (normalizedDistance?.isEmpty == false) ? normalizedDistance : nil
        let isOpen = locationVM.isLikelyOpen

        if name == nil, distance == nil, isOpen == nil {
            return nil
        }

        return PharmacyInfo(
            name: name,
            isOpen: isOpen,
            distanceText: distance
        )
    }

    private var uniqueMedicines: [Medicine] {
        var seen = Set<UUID>()
        return medicinePackages.compactMap { entry -> Medicine? in
            guard !entry.isDeleted else { return nil }
            let id = entry.medicine.id
            guard seen.insert(id).inserted else { return nil }
            return entry.medicine
        }
    }

    private var cabinetListView: some View {
        let viewState = activeFilter == nil ? cachedShelfState : filteredShelfState(cachedShelfState)
        return List {
            filterChipsSection
            standardCabinetSections(viewState: viewState)
        }
    }

    private func recomputeShelfState() {
        let entries = Array(medicinePackages)
        let shelfState = viewModel.shelfViewState(
            entries: entries,
            option: options.first,
            cabinets: Array(cabinets),
            favoriteMedicineIDs: favoritesStore.favoriteMedicineIDs
        )
        cachedShelfState = shelfSections(from: shelfState)
        rowSnapshotsByEntryID = viewModel.buildRowSnapshots(entries: entries, option: options.first)
    }

    @ViewBuilder
    private func standardCabinetSections(viewState: ShelfViewState) -> some View {
        if isShelfEmpty(viewState) {
            Section {
                emptyCabinetContent
                    .listRowInsets(
                        EdgeInsets(
                            top: 12,
                            leading: 0,
                            bottom: 10,
                            trailing: 0
                        )
                    )
                    .listRowBackground(Color(.systemBackground))
            }
            .listSectionSeparator(.hidden)
        }

        if !viewState.pinnedMedicineEntries.isEmpty || !viewState.otherMedicineEntries.isEmpty {
            Section {
                ForEach(viewState.pinnedMedicineEntries, id: \.id) { entry in
                    shelfRow(for: entry, orderedEntriesByCabinetID: viewState.orderedEntriesByCabinetID)
                }
                ForEach(viewState.otherMedicineEntries, id: \.id) { entry in
                    shelfRow(for: entry, orderedEntriesByCabinetID: viewState.orderedEntriesByCabinetID)
                }
            }
            .listSectionSeparator(.hidden)
        }

        if !viewState.cabinetEntries.isEmpty {
            Section(header: sectionHeader("Armadietti")) {
                ForEach(viewState.cabinetEntries, id: \.id) { entry in
                    shelfRow(for: entry, orderedEntriesByCabinetID: viewState.orderedEntriesByCabinetID)
                }
            }
            .listSectionSeparator(.hidden)
        }
    }

    private func isShelfEmpty(_ viewState: ShelfViewState) -> Bool {
        viewState.pinnedMedicineEntries.isEmpty
            && viewState.cabinetEntries.isEmpty
            && viewState.otherMedicineEntries.isEmpty
    }

    private var emptyCabinetContent: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .topLeading) {
                Image("empty_cabinet")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.emptyStateImageHeight)
                    .scaleEffect(Layout.emptyStateImageScale)
                    .offset(x: Layout.emptyStateImageHorizontalOffset)
                    .padding(.top, Layout.emptyStateImageTopPadding)
                    .padding(.bottom, Layout.emptyStateImageBottomPadding)
                    .clipped()
                    .accessibilityHidden(true)

                Text("Aggiungi i medicinali\nche vuoi tenere\nsotto controllo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: Layout.emptyStateOverlayTextMaxWidth, alignment: .leading)
                    .padding(.leading, Layout.emptyStateOverlayLeadingPadding)
                    .padding(.top, Layout.emptyStateOverlayTopPadding)
            }

            Text("Potrai vedere le scorte, sapere quando stanno per finire e gestire refill e restore facilmente.")
            .font(.title2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Layout.emptyStateBottomTextTopPadding)
            .padding(.horizontal, Layout.emptyStateBottomTextHorizontalInset)
        }
        .padding(.horizontal, Layout.horizontalInset)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color(.systemBackground))
    }

    private func shelfSections(from shelfState: CabinetViewModel.ShelfViewState) -> ShelfViewState {
        var pinnedMedicineEntries: [CabinetViewModel.ShelfEntry] = []
        var cabinetEntries: [CabinetViewModel.ShelfEntry] = []
        var otherMedicineEntries: [CabinetViewModel.ShelfEntry] = []
        for entry in shelfState.entries {
            if case .cabinet = entry.kind {
                cabinetEntries.append(entry)
            } else if case .medicinePackage(let medicineEntry) = entry.kind {
                if favoritesStore.isFavoriteMedicine(id: medicineEntry.medicine.id) {
                    pinnedMedicineEntries.append(entry)
                } else {
                    otherMedicineEntries.append(entry)
                }
            }
        }
        return ShelfViewState(
            pinnedMedicineEntries: pinnedMedicineEntries,
            cabinetEntries: sortFavoriteCabinetsFirst(cabinetEntries),
            otherMedicineEntries: otherMedicineEntries,
            orderedEntriesByCabinetID: shelfState.orderedEntriesByCabinetID
        )
    }

    @ViewBuilder
    private func shelfRow(
        for entry: CabinetViewModel.ShelfEntry,
        orderedEntriesByCabinetID: [String: [MedicinePackage]]
    ) -> some View {
        switch entry.kind {
        case .cabinet(let cabinet):
            cabinetRow(
                for: cabinet,
                entries: orderedEntriesByCabinetID[cabinet.id.uuidString] ?? []
            )
        case .medicinePackage(let entry):
            row(for: entry)
        }
    }

    private func sortFavoriteCabinetsFirst(
        _ entries: [CabinetViewModel.ShelfEntry]
    ) -> [CabinetViewModel.ShelfEntry] {
        var pinnedCabinets: [CabinetViewModel.ShelfEntry] = []
        var regularCabinets: [CabinetViewModel.ShelfEntry] = []

        for entry in entries {
            guard case .cabinet(let cabinet) = entry.kind else {
                regularCabinets.append(entry)
                continue
            }

            if favoritesStore.isFavoriteCabinet(id: cabinet.id) {
                pinnedCabinets.append(entry)
            } else {
                regularCabinets.append(entry)
            }
        }

        return pinnedCabinets + regularCabinets
    }

    private func sectionHeader(_ title: String, topPadding: CGFloat = 12) -> some View {
        Text(title)
            .textCase(nil)
            .padding(.top, topPadding)
    }

    private func swipeLabel(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
    }

    // MARK: - Filters

    private enum CabinetFilter: Hashable, Identifiable {
        case stock
        case therapies
        case label(String)
        case custom(CabinetCustomFilterRecord)

        var id: String {
            switch self {
            case .stock: return "stock"
            case .therapies: return "therapies"
            case .label(let l): return "label-\(l.lowercased())"
            case .custom(let filter): return "custom-\(filter.id.uuidString)"
            }
        }

        var title: String {
            switch self {
            case .stock: return "Scorte"
            case .therapies: return "Terapie"
            case .label(let l): return l
            case .custom(let filter): return filter.name
            }
        }
    }

    private var availableFilters: [CabinetFilter] {
        customFilters
            .sorted(by: { lhs, rhs in
                if lhs.position == rhs.position {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.position < rhs.position
            })
            .map(CabinetFilter.custom)
    }

    private func filteredShelfState(_ viewState: ShelfViewState) -> ShelfViewState {
        guard let filter = activeFilter else { return viewState }
        let matchingIDs = matchingMedicineIDs(for: filter)

        func filterEntries(_ entries: [CabinetViewModel.ShelfEntry]) -> [CabinetViewModel.ShelfEntry] {
            entries.filter { shelfEntry in
                if case .medicinePackage(let mp) = shelfEntry.kind {
                    return matchingIDs.contains(mp.medicine.id)
                }
                return false
            }
        }

        return ShelfViewState(
            pinnedMedicineEntries: filterEntries(viewState.pinnedMedicineEntries),
            cabinetEntries: [],
            otherMedicineEntries: filterEntries(viewState.otherMedicineEntries),
            orderedEntriesByCabinetID: viewState.orderedEntriesByCabinetID
        )
    }

    private func filterCount(_ filter: CabinetFilter) -> Int {
        cachedFilterChipPresentations[filter.id]?.count ?? 0
    }

    @ViewBuilder
    private var filterChipsSection: some View {
        let filters = availableFilters
        if !isShelfEmpty(cachedShelfState) {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters) { filter in
                            let isActive = activeFilter?.id == filter.id
                            let count = filterCount(filter)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if activeFilter?.id == filter.id {
                                        activeFilter = nil
                                    } else {
                                        activeFilter = filter
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(filter.title)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Text("\(count)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(isActive ? Color.white.opacity(0.7) : Color(.tertiaryLabel))
                                    if let indicator = filterIndicator(for: filter) {
                                        Image(systemName: indicator.systemImage)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(indicator.color)
                                    }
                                }
                                .foregroundStyle(isActive ? Color.white : Color(.secondaryLabel))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isActive ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(isActive ? Color.clear : Color(.separator), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if case .custom(let customFilter) = filter {
                                    Button("Modifica") {
                                        customFilterEditorMode = .edit(customFilter)
                                    }
                                    Button("Elimina", role: .destructive) {
                                        pendingCustomFilterDeletion = customFilter
                                    }
                                }
                            }
                        }
                        addCustomFilterChip
                    }
                    .padding(.horizontal, Layout.horizontalInset)
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
    }

    private var addCustomFilterChip: some View {
        Button {
            customFilterEditorMode = .create
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Crea filtro")
    }

    // MARK: - Helpers
    private func recomputeFilterChipPresentations() {
        let stockStatuses = Dictionary(uniqueKeysWithValues: uniqueMedicines.map { medicine in
            (medicine.id, computeStockStatus(for: medicine))
        })
        cachedMedicineStockStatuses = stockStatuses

        var presentations: [String: FilterChipPresentation] = [:]
        for filter in availableFilters {
            let medicines = matchingMedicines(for: filter, stockStatuses: stockStatuses)
            let kpi = viewModel.computeSummaryDisplayData(
                medicines: medicines,
                option: options.first,
                pharmacy: nil
            ).kpi
            presentations[filter.id] = FilterChipPresentation(
                count: medicines.count,
                indicator: stockFilterIndicator(for: kpi)
            )
        }
        cachedFilterChipPresentations = presentations
    }

    private func stockFilterIndicator(
        for kpi: CabinetViewModel.SummaryKPI
    ) -> StockFilterIndicator {
        let unknownCount = max(0, kpi.totalCount - kpi.coveredCount - kpi.refillCount)

        if kpi.totalCount == 0 || kpi.coveredCount == kpi.totalCount {
            return .ok
        }
        if kpi.stockStatusTone == .critical || (kpi.nextRefillInDays ?? Int.max) <= 0 {
            return .critical
        }
        if unknownCount > 0 {
            return .warning
        }
        if let nextRefillInDays = kpi.nextRefillInDays {
            if nextRefillInDays == 1 {
                return .warning
            }
            if nextRefillInDays > 1 {
                return .protected
            }
        }
        if kpi.refillCount > 0 {
            return .protected
        }
        return .warning
    }

    private func filterIndicator(for filter: CabinetFilter) -> StockFilterIndicator? {
        cachedFilterChipPresentations[filter.id]?.indicator
    }

    private func matchingMedicines(
        for filter: CabinetFilter,
        stockStatuses: [UUID: StockStatus]? = nil
    ) -> [Medicine] {
        let ids = matchingMedicineIDs(for: filter, stockStatuses: stockStatuses)
        return uniqueMedicines.filter { ids.contains($0.id) }
    }

    private func matchingMedicineIDs(
        for filter: CabinetFilter,
        stockStatuses: [UUID: StockStatus]? = nil
    ) -> Set<UUID> {
        switch filter {
        case .stock:
            return stockFilterMedicineIDs(using: stockStatuses)
        case .therapies:
            return Set(
                uniqueMedicines.compactMap { medicine in
                    !(medicine.therapies ?? []).isEmpty ? medicine.id : nil
                }
            )
        case .label(let label):
            let key = normalizedFilterToken(label)
            return Set(
                uniqueMedicines.compactMap { medicine in
                    medicine.displayLabels.contains {
                        normalizedFilterToken($0) == key
                    } ? medicine.id : nil
                }
            )
        case .custom(let filter):
            return customFilterMedicineIDs(filter, stockStatuses: stockStatuses)
        }
    }

    private func customFilterMedicineIDs(
        _ filter: CabinetCustomFilterRecord,
        stockStatuses: [UUID: StockStatus]? = nil
    ) -> Set<UUID> {
        let trimmedQuery = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard let expression = try? customFilterParser.parse(trimmedQuery) else { return [] }

        let resolvedStatuses = stockStatuses ?? cachedMedicineStockStatuses
        return Set(
            uniqueMedicines.compactMap { medicine in
                let context = customFilterContext(for: medicine, stockStatuses: resolvedStatuses)
                return customFilterEvaluator.matches(expression, in: context) ? medicine.id : nil
            }
        )
    }

    private func normalizedFilterToken(
        _ token: String
    ) -> String {
        token
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func customFilterContext(
        for medicine: Medicine,
        stockStatuses: [UUID: StockStatus]
    ) -> CabinetCustomFilterContext {
        let stock: CabinetCustomFilterStockValue
        switch stockStatus(for: medicine, from: stockStatuses) {
        case .ok:
            stock = .ok
        case .critical:
            stock = .out
        case .low, .unknown:
            stock = .low
        }

        return CabinetCustomFilterContext(
            name: medicine.nome,
            labels: medicine.displayLabels,
            stock: stock,
            hasTherapy: !(medicine.therapies ?? []).isEmpty,
            requiresPrescription: medicine.obbligo_ricetta,
            cabinetNames: cabinetNames(for: medicine),
            deadline: deadlineValue(for: medicine)
        )
    }

    private func cabinetNames(for medicine: Medicine) -> [String] {
        let names = medicinePackages.compactMap { entry -> String? in
            guard !entry.isDeleted else { return nil }
            guard entry.medicine.id == medicine.id else { return nil }
            return entry.cabinet?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return names.filter { !$0.isEmpty }
    }

    private func deadlineValue(for medicine: Medicine) -> CabinetCustomFilterDeadlineValue {
        let statuses = medicinePackages.compactMap { entry -> Medicine.DeadlineStatus? in
            guard !entry.isDeleted else { return nil }
            guard entry.medicine.id == medicine.id else { return nil }
            return entry.deadlineStatus
        }

        if statuses.contains(.expired) {
            return .expired
        }
        if statuses.contains(.expiringSoon) {
            return .soon
        }
        if statuses.contains(.ok) {
            return .ok
        }
        return .none
    }

    private func previewPresentation(for query: String) -> FilterChipPresentation? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }
        guard (try? customFilterParser.parse(trimmedQuery)) != nil else { return nil }

        let temporaryFilter = CabinetCustomFilterRecord(
            id: UUID(),
            ownerUserId: UserIdentityProvider.shared.userId,
            name: "Anteprima",
            query: trimmedQuery,
            position: 0,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
        let statuses = resolvedStockStatuses()
        let matchingIDs = customFilterMedicineIDs(temporaryFilter, stockStatuses: statuses)
        let medicines = uniqueMedicines.filter { matchingIDs.contains($0.id) }
        let kpi = viewModel.computeSummaryDisplayData(
            medicines: medicines,
            option: options.first,
            pharmacy: nil
        ).kpi
        return FilterChipPresentation(count: medicines.count, indicator: stockFilterIndicator(for: kpi))
    }

    private func resolvedStockStatuses() -> [UUID: StockStatus] {
        if !cachedMedicineStockStatuses.isEmpty {
            return cachedMedicineStockStatuses
        }
        return Dictionary(uniqueKeysWithValues: uniqueMedicines.map { medicine in
            (medicine.id, computeStockStatus(for: medicine))
        })
    }

    private func stockFilterMedicineIDs(using stockStatuses: [UUID: StockStatus]? = nil) -> Set<UUID> {
        let resolvedStatuses = stockStatuses ?? cachedMedicineStockStatuses
        let problematicIDs = Set(
            uniqueMedicines.compactMap { medicine in
                stockStatus(for: medicine, from: resolvedStatuses) == .ok ? nil : medicine.id
            }
        )

        if !problematicIDs.isEmpty {
            return problematicIDs
        }

        return Set(
            uniqueMedicines.compactMap { medicine in
                stockStatus(for: medicine, from: resolvedStatuses) == .ok ? medicine.id : nil
            }
        )
    }

    private func stockStatus(
        for medicine: Medicine,
        from stockStatuses: [UUID: StockStatus]
    ) -> StockStatus {
        stockStatuses[medicine.id] ?? computeStockStatus(for: medicine)
    }

    private func computeStockStatus(for medicine: Medicine) -> StockStatus {
        guard let context = medicine.managedObjectContext else { return .unknown }
        let builder = CoreDataSnapshotBuilder(context: context)
        let snapshot = builder.makeMedicineSnapshot(medicine: medicine, logs: Array(medicine.logs ?? []))
        let optionSnapshot = builder.makeOptionSnapshot(option: options.first)
        return viewModel.sectionCalculator.stockStatus(for: snapshot, option: optionSnapshot)
    }

    private var newCabinetSheet: some View {
        NavigationStack {
            Form {
                Section("Nome armadietto") {
                    TextField("Es. Casa", text: $newCabinetName)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Nuovo armadietto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { isNewCabinetPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        createCabinet()
                        isNewCabinetPresented = false
                    }
                    .disabled(trimmedCabinetName.isEmpty)
                }
            }
        }
    }

    private var trimmedCabinetName: String {
        newCabinetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createCabinet() {
        let name = trimmedCabinetName
        guard !name.isEmpty else { return }
        do {
            _ = try appDataStore.provider.medicines.createCabinet(name: name)
            newCabinetName = ""
        } catch {
            // Keep current behavior: fail silently without interrupting the sheet flow.
        }
    }

    private func createCustomFilter(name: String, query: String) {
        do {
            let created = try appDataStore.provider.medicines.createCustomFilter(name: name, query: query)
            if activeFilter == nil {
                activeFilter = .custom(created)
            }
            reloadFetchedState()
            recomputeAllCachedState()
        } catch {
            // Keep current behavior: fail silently in this flow.
        }
    }

    private func updateCustomFilter(filterID: UUID, name: String, query: String) {
        do {
            let updated = try appDataStore.provider.medicines.updateCustomFilter(
                id: filterID,
                name: name,
                query: query
            )
            if case .custom(let activeCustom)? = activeFilter, activeCustom.id == filterID {
                activeFilter = .custom(updated)
            }
            reloadFetchedState()
            recomputeAllCachedState()
        } catch {
            // Keep current behavior: fail silently in this flow.
        }
    }

    private func deleteCustomFilter(filterID: UUID) {
        do {
            try appDataStore.provider.medicines.deleteCustomFilter(id: filterID)
            if case .custom(let activeCustom)? = activeFilter, activeCustom.id == filterID {
                activeFilter = nil
            }
            pendingCustomFilterDeletion = nil
            reloadFetchedState()
            recomputeAllCachedState()
        } catch {
            // Keep current behavior: fail silently in this flow.
        }
    }

    private func row(for entry: MedicinePackage) -> some View {
        let entryKey = entry.id.uuidString
        let rowSnapshot = rowSnapshotsByEntryID[entryKey]
        let shouldShowRx = rowSnapshot?.shouldShowPrescription ?? viewModel.shouldShowPrescriptionAction(for: entry)
        return MedicineSwipeRow(
            entry: entry,
            isSelected: viewModel.selectedEntryIDs.contains(entry.id),
            isInSelectionMode: viewModel.isSelecting,
            shouldShowPrescription: shouldShowRx,
            isPinned: favoritesStore.isFavoriteMedicine(id: entry.medicine.id),
            onTap: {
                if viewModel.isSelecting {
                    viewModel.toggleSelection(for: entry.id)
                } else {
                    selectedEntrySelection = EntrySelection(id: entry.id)
                }
            },
            onLongPress: {
                selectedEntrySelection = EntrySelection(id: entry.id)
                Haptics.impact(.medium)
            },
            onToggleSelection: { viewModel.toggleSelection(for: entry.id) },
            onEnterSelection: { viewModel.enterSelectionMode(with: entry.id) },
            onMarkPurchased: {
                let token = operationToken(for: .purchase, entry: entry)
                let didRecord = appDataStore.provider.medicines.recordPurchase(
                    medicine: entry.medicine,
                    package: entry.package,
                    medicinePackage: entry,
                    operationId: token.id
                )
                handleOperationResult(didRecord, key: token.key)
            },
            onRequestPrescription: shouldShowRx ? {
                let token = operationToken(for: .prescriptionRequest, entry: entry)
                let didRecord = appDataStore.provider.medicines.recordPrescriptionRequest(
                    medicine: entry.medicine,
                    package: entry.package,
                    medicinePackage: entry,
                    operationId: token.id
                )
                handleOperationResult(didRecord, key: token.key)
            } : nil,
            onMove: { entryToMoveSelection = EntrySelection(id: entry.id) },
            subtitleMode: .activeTherapies,
            snapshot: rowSnapshot?.presentation
        )
        .accessibilityIdentifier("MedicineRow_\(entry.id.uuidString)")
        .listRowInsets(
            EdgeInsets(
                top: 1,
                leading: Layout.horizontalInset,
                bottom: 1,
                trailing: Layout.horizontalInset
            )
        )
    }

    private func currentEntry(id: UUID) -> MedicinePackage? {
        medicinePackages.first { $0.id == id && !$0.isDeleted }
    }

    private func cabinetRow(for cabinet: Cabinet, entries: [MedicinePackage]) -> some View {
        let isFavoriteCabinet = favoritesStore.isFavoriteCabinet(id: cabinet.id)
        let cabinetKey = cabinet.id.uuidString
        return Button {
            activeCabinetID = cabinetKey
        } label: {
            CabinetCardView(cabinet: cabinet)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            NavigationLink(
                destination: CabinetDetailView(cabinet: cabinet, entries: entries, viewModel: viewModel),
                isActive: Binding(
                    get: { activeCabinetID == cabinetKey },
                    set: { newValue in
                        if !newValue { activeCabinetID = nil }
                    }
                )
            ) {
                EmptyView()
            }
            .hidden()
        )
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                favoritesStore.toggleFavoriteCabinet(id: cabinet.id)
            } label: {
                swipeLabel(
                    isFavoriteCabinet ? "Rimuovi preferiti" : "Preferito",
                    systemImage: isFavoriteCabinet ? "pin.fill" : "pin"
                )
            }
            .tint(isFavoriteCabinet ? .orange : .accentColor)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden, edges: .all)
        .listRowInsets(
            EdgeInsets(
                top: 1,
                leading: Layout.horizontalInset,
                bottom: 1,
                trailing: Layout.horizontalInset
            )
        )
    }

    private func operationToken(for action: OperationAction, entry: MedicinePackage) -> (id: UUID, key: OperationKey) {
        let key = OperationKey.medicineAction(
            action: action,
            medicineId: entry.medicine.id,
            packageId: entry.package.id,
            source: .cabinet
        )
        let id = OperationIdProvider.shared.operationId(for: key, ttl: 3)
        return (id, key)
    }

    private func handleOperationResult(_ didSucceed: Bool, key: OperationKey) {
        if didSucceed {
            reloadFetchedState()
            recomputeAllCachedState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                OperationIdProvider.shared.clear(key)
            }
        } else {
            OperationIdProvider.shared.clear(key)
        }
    }

    private enum PharmacyRouteMode {
        case walking
        case driving
    }

    private func routeMinutes(for mode: PharmacyRouteMode) -> Int? {
        guard let distance = locationVM.distanceMeters else { return nil }
        switch mode {
        case .walking:
            return locationVM.walkingRouteMinutes ?? max(1, Int(round(distance / 83.0)))
        case .driving:
            return locationVM.drivingRouteMinutes ?? max(1, Int(round(distance / 750.0)))
        }
    }

    private var pharmacyRouteSummaryText: String? {
        let walkingText = routeMinutes(for: .walking).map { "\($0) min a piedi" }
        let drivingText = routeMinutes(for: .driving).map { "\($0) min in auto" }
        let parts = [walkingText, drivingText].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

}
