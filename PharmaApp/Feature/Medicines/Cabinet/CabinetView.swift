import SwiftUI
import CoreData
import WidgetKit

/// Vista dedicata al tab "Armadietto" (ex ramo medicines di FeedView)
struct CabinetView: View {
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
        static let horizontalInset: CGFloat = 28
        static let summaryTrailingInset: CGFloat = 40
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

    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appDataStore: AppDataStore
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @StateObject private var viewModel = CabinetViewModel()
    @StateObject private var locationVM = LocationSearchViewModel()

    @State private var medicinePackages: [MedicinePackage] = []
    @State private var options: [Option] = []
    @State private var cabinets: [Cabinet] = []

    @State private var activeCabinetID: String?
    @State private var entryToMove: MedicinePackage?
    @State private var isNewCabinetPresented = false
    @State private var newCabinetName = ""
    @State private var isCatalogAddPresented = false
    @State private var shouldAutoStartCatalogScan = false
    @State private var isProfilePresented = false
    @State private var selectedEntry: MedicinePackage?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.75)
    @State private var missedDoseSheet: MissedDoseSheetState?
    @State private var cachedSummaryLines: [String] = ["Per ora non ci sono azioni da fare."]
    @State private var cachedInlineAction: String = "Per ora nessuna azione"
    @State private var cachedShelfState: ShelfViewState = .empty
    @State private var rowSnapshotsByEntryID: [String: CabinetViewModel.CabinetRowSnapshot] = [:]
    @State private var syncWorkItem: DispatchWorkItem?
    @State private var hasStartedObservation = false

    var body: some View {
        cabinetRootView
    }

    private var cabinetRootView: some View {
        cabinetListWithNavigation
    }

    private var cabinetListWithNavigation: some View {
        cabinetListWithNewCabinetSheet
            .background {
                NavigationBarInsetConfigurator(horizontalInset: Layout.horizontalInset)
            }
            .navigationTitle("Armadietto")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.automatic, for: .navigationBar)
            .toolbar {
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
                guard !hasStartedObservation else { return }
                hasStartedObservation = true
                locationVM.ensureStarted()
                reloadFetchedState()
                recomputeAllCachedState()
                handlePendingRoute(appRouter.pendingRoute)
                for await _ in appDataStore.provider.observe(
                    scopes: [.medicines, .therapies, .logs, .stocks, .cabinets, .options]
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
            .onChange(of: appRouter.pendingRoute) { route in
                handlePendingRoute(route)
            }
    }

    private func recomputeAllCachedState() {
        recomputeSummaryLines()
        recomputeShelfState()
        syncSummaryToWidgetDebounced()
    }

    private func reloadFetchedState() {
        do {
            let snapshot = try appDataStore.provider.medicines.fetchCabinetSnapshot()
            medicinePackages = snapshot.medicinePackages
            options = snapshot.options
            cabinets = snapshot.cabinets
        } catch {
            medicinePackages = []
            options = []
            cabinets = []
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
    }

    private var cabinetListWithDetailSheet: some View {
        cabinetListStyled
            .sheet(isPresented: Binding(
                get: { selectedEntry != nil && !(selectedEntry?.isDeleted ?? true) },
                set: { newValue in if !newValue { selectedEntry = nil } }
            )) {
                if let entry = selectedEntry, !entry.isDeleted, entry.managedObjectContext != nil {
                    MedicineDetailView(
                        medicine: entry.medicine,
                        package: entry.package,
                        medicinePackage: entry
                    )
                    .presentationDetents([.fraction(0.75), .large], selection: $detailSheetDetent)
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $entryToMove) { entry in
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
            .sheet(item: $missedDoseSheet) { state in
                MissedDoseIntakeSheet(candidate: state.candidate) { takenAt, nextAction in
                    let log = viewModel.actionService.recordMissedDoseIntake(
                        candidate: state.candidate,
                        takenAt: takenAt,
                        nextAction: nextAction,
                        operationId: state.operationId
                    )
                    if let key = state.operationKey {
                        handleOperationResult(log, key: key)
                    }
                }
            }
    }

    private var cabinetListStyled: some View {
        cabinetListView
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden, edges: .all)
            .listSectionSpacingIfAvailable(4)
            .listRowSpacing(18)
            .listStyle(.plain)
            .padding(.top, 16)
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .scrollDisabled(isShelfEmpty(cachedShelfState))
            .scrollIndicators(.hidden)
    }

    private var summaryTextView: some View {
        Text(cachedSummaryLines.joined(separator: "\n"))
            .font(.title3.weight(.regular))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
    }

    private func computeSummaryDisplayData() -> CabinetViewModel.SummaryDisplayData {
        // Pharmacy suggestion temporaneamente disabilitata
        viewModel.computeSummaryDisplayData(
            medicines: uniqueMedicines,
            option: options.first,
            pharmacy: nil
        )
    }

    private var uniqueMedicines: [Medicine] {
        var seen = Set<UUID>()
        return medicinePackages.compactMap { entry -> Medicine? in
            guard !entry.isDeleted, entry.managedObjectContext != nil else { return nil }
            let id = entry.medicine.id
            guard seen.insert(id).inserted else { return nil }
            return entry.medicine
        }
    }

    private var cabinetListView: some View {
        let viewState = cachedShelfState
        return List {
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
        Section {
            summaryTextView
                .listRowInsets(
                    EdgeInsets(
                        top: 40,
                        leading: Layout.horizontalInset,
                        bottom: 40,
                        trailing: Layout.summaryTrailingInset
                    )
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)

        if appVM.suggestNearestPharmacies {
            Section {
                smartBannerCard
                    .listRowInsets(
                        EdgeInsets(
                            top: 12,
                            leading: Layout.horizontalInset,
                            bottom: 16,
                            trailing: Layout.horizontalInset
                        )
                    )
                    .listRowBackground(Color.clear)
            }
            .listSectionSeparator(.hidden)
        }

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
                    .listRowBackground(Color.white)
            }
            .listSectionSeparator(.hidden)
        }

        if !viewState.pinnedMedicineEntries.isEmpty {
            Section {
                ForEach(viewState.pinnedMedicineEntries, id: \.id) { entry in
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

        if !viewState.otherMedicineEntries.isEmpty {
            Section {
                ForEach(viewState.otherMedicineEntries, id: \.id) { entry in
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

            Text("Potrai vedere le scorte, sapere quando stanno per finire e registrare acquisti e assunzioni facilmente.")
            .font(.title2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Layout.emptyStateBottomTextTopPadding)
            .padding(.horizontal, Layout.emptyStateBottomTextHorizontalInset)
        }
        .padding(.horizontal, Layout.horizontalInset)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color.white)
    }

    private func shelfSections(from shelfState: CabinetViewModel.ShelfViewState) -> ShelfViewState {
        var pinnedMedicineEntries: [CabinetViewModel.ShelfEntry] = []
        var cabinetEntries: [CabinetViewModel.ShelfEntry] = []
        var otherMedicineEntries: [CabinetViewModel.ShelfEntry] = []
        for entry in shelfState.entries {
            if case .cabinet = entry.kind {
                cabinetEntries.append(entry)
            } else if case .medicinePackage(let medicineEntry) = entry.kind {
                if favoritesStore.isFavorite(medicineEntry) {
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

            if favoritesStore.isFavorite(cabinet) {
                pinnedCabinets.append(entry)
            } else {
                regularCabinets.append(entry)
            }
        }

        return pinnedCabinets + regularCabinets
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .padding(.horizontal, Layout.horizontalInset)
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

    // MARK: - Helpers
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

    private func row(for entry: MedicinePackage) -> some View {
        let entryKey = entry.id.uuidString
        let rowSnapshot = rowSnapshotsByEntryID[entryKey]
        let shouldShowRx = rowSnapshot?.shouldShowPrescription ?? viewModel.shouldShowPrescriptionAction(for: entry)
        return MedicineSwipeRow(
            entry: entry,
            isSelected: viewModel.selectedEntries.contains(entry),
            isInSelectionMode: viewModel.isSelecting,
            shouldShowPrescription: shouldShowRx,
            isPinned: favoritesStore.isFavorite(entry),
            onTap: {
                if viewModel.isSelecting {
                    viewModel.toggleSelection(for: entry)
                } else {
                    selectedEntry = entry
                }
            },
            onLongPress: {
                selectedEntry = entry
                Haptics.impact(.medium)
            },
            onToggleSelection: { viewModel.toggleSelection(for: entry) },
            onEnterSelection: { viewModel.enterSelectionMode(with: entry) },
            onMarkTaken: {
                beginMarkTaken(for: entry)
            },
            onMarkPurchased: {
                let token = operationToken(for: .purchase, entry: entry)
                let log = viewModel.actionService.markAsPurchased(for: entry, operationId: token.id)
                handleOperationResult(log, key: token.key)
            },
            onRequestPrescription: shouldShowRx ? {
                let token = operationToken(for: .prescriptionRequest, entry: entry)
                let log = viewModel.actionService.requestPrescription(for: entry, operationId: token.id)
                handleOperationResult(log, key: token.key)
            } : nil,
            onMove: { entryToMove = entry },
            subtitleMode: .activeTherapies,
            snapshot: rowSnapshot?.presentation
        )
        .accessibilityIdentifier("MedicineRow_\(entry.id.uuidString)")
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

    private func beginMarkTaken(for entry: MedicinePackage) {
        guard hasSufficientStockForIntake(entry) else { return }

        let token = operationToken(for: .intake, entry: entry)
        if let candidate = viewModel.actionService.missedDoseCandidate(for: entry) {
            missedDoseSheet = MissedDoseSheetState(
                candidate: candidate,
                operationId: token.id,
                operationKey: token.key
            )
            return
        }

        let log = viewModel.actionService.markAsTaken(for: entry, operationId: token.id)
        handleOperationResult(log, key: token.key)
    }

    private func hasSufficientStockForIntake(_ entry: MedicinePackage) -> Bool {
        appDataStore.provider.medicines.hasSufficientStockForIntake(entryId: entry.id)
    }

    private func cabinetRow(for cabinet: Cabinet, entries: [MedicinePackage]) -> some View {
        let isFavoriteCabinet = favoritesStore.isFavorite(cabinet)
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
                favoritesStore.toggleFavorite(cabinet)
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

    private func handleOperationResult(_ log: Log?, key: OperationKey) {
        if log != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                OperationIdProvider.shared.clear(key)
            }
        } else {
            OperationIdProvider.shared.clear(key)
        }
    }

    // MARK: - Banner
    private var smartBannerCard: some View {
        Button {
            appVM.isStocksIndexPresented = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Circle().fill(Color.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rifornisci i farmaci in esaurimento")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Ti suggeriamo la farmacia più comoda in questo momento.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
        }
        .buttonStyle(.plain)
    }

}

private struct NavigationBarInsetConfigurator: UIViewControllerRepresentable {
    let horizontalInset: CGFloat

    func makeUIViewController(context: Context) -> Controller {
        Controller(horizontalInset: horizontalInset)
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.horizontalInset = horizontalInset
        uiViewController.applyInsetIfNeeded()
    }

    final class Controller: UIViewController {
        var horizontalInset: CGFloat
        private weak var observedNavigationBar: UINavigationBar?
        private var previousDirectionalLayoutMargins: NSDirectionalEdgeInsets?

        init(horizontalInset: CGFloat) {
            self.horizontalInset = horizontalInset
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyInsetIfNeeded()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restoreInsetsIfNeeded()
        }

        func applyInsetIfNeeded() {
            guard let navigationBar = navigationController?.navigationBar else { return }

            if observedNavigationBar !== navigationBar {
                restoreInsetsIfNeeded()
                observedNavigationBar = navigationBar
                previousDirectionalLayoutMargins = navigationBar.directionalLayoutMargins
            } else if previousDirectionalLayoutMargins == nil {
                previousDirectionalLayoutMargins = navigationBar.directionalLayoutMargins
            }

            var margins = navigationBar.directionalLayoutMargins
            margins.leading = horizontalInset
            margins.trailing = horizontalInset
            navigationBar.directionalLayoutMargins = margins
            navigationBar.setNeedsLayout()
            navigationBar.layoutIfNeeded()
        }

        private func restoreInsetsIfNeeded() {
            guard
                let navigationBar = observedNavigationBar,
                let previousDirectionalLayoutMargins
            else { return }

            navigationBar.directionalLayoutMargins = previousDirectionalLayoutMargins
            navigationBar.setNeedsLayout()
            navigationBar.layoutIfNeeded()
            observedNavigationBar = nil
            self.previousDirectionalLayoutMargins = nil
        }
    }
}
