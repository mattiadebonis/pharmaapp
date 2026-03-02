import SwiftUI
import CoreData
import WidgetKit

/// Vista dedicata al tab "Armadietto" (ex ramo medicines di FeedView)
struct CabinetView: View {
    private struct ShelfViewState {
        let favoriteEntries: [CabinetViewModel.ShelfEntry]
        let cabinetEntries: [CabinetViewModel.ShelfEntry]
        let otherMedicineEntries: [CabinetViewModel.ShelfEntry]
        let orderedEntriesByCabinetID: [NSManagedObjectID: [MedicinePackage]]

        static let empty = ShelfViewState(
            favoriteEntries: [],
            cabinetEntries: [],
            otherMedicineEntries: [],
            orderedEntriesByCabinetID: [:]
        )
    }

    private enum Layout {
        static let horizontalInset: CGFloat = 28
        static let summaryTrailingInset: CGFloat = 40
    }

    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.managedObjectContext) private var managedObjectContext
    @StateObject private var viewModel = CabinetViewModel()
    @StateObject private var locationVM = LocationSearchViewModel()

    @FetchRequest(fetchRequest: MedicinePackage.extractEntries())
    private var medicinePackages: FetchedResults<MedicinePackage>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Cabinet.extractCabinets())
    private var cabinets: FetchedResults<Cabinet>

    @State private var activeCabinetID: NSManagedObjectID?
    @State private var entryToMove: MedicinePackage?
    @State private var isNewCabinetPresented = false
    @State private var newCabinetName = ""
    @State private var isCatalogAddPresented = false
    @State private var shouldAutoStartCatalogScan = false
    @State private var isProfilePresented = false
    @State private var selectedEntry: MedicinePackage?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.75)
    @State private var missedDoseSheet: MissedDoseSheetState?
    @State private var cachedSummaryLines: [String] = ["Tutto sotto controllo!"]
    @State private var cachedShelfState: ShelfViewState = .empty
    @State private var rowSnapshotsByEntryID: [NSManagedObjectID: CabinetViewModel.CabinetRowSnapshot] = [:]
    @State private var syncWorkItem: DispatchWorkItem?

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
            .onAppear {
                locationVM.ensureStarted()
                recomputeAllCachedState()
                handlePendingRoute(appRouter.pendingRoute)
            }
            .onChange(of: medicinePackages.count) { _ in
                recomputeAllCachedState()
            }
            .onChange(of: cabinets.count) { _ in
                recomputeAllCachedState()
            }
            .onChange(of: options.count) { _ in
                recomputeAllCachedState()
            }
            .onReceive(favoritesStore.objectWillChange) { _ in
                recomputeShelfState()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSManagedObjectContextObjectsDidChange,
                    object: managedObjectContext
                )
            ) { notification in
                guard hasRelevantCabinetChanges(notification) else { return }
                recomputeAllCachedState()
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

    private func recomputeSummaryLines() {
        cachedSummaryLines = computeSummaryLines()
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
            CabinetSummarySharedStore.write(cachedSummaryLines)
            WidgetCenter.shared.reloadTimelines(ofKind: "CabinetSummaryWidget")
        }
        syncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func hasRelevantCabinetChanges(_ notification: Notification) -> Bool {
        let keys: [String] = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]

        for key in keys {
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: isRelevantCabinetObject) {
                return true
            }
        }

        return false
    }

    private func isRelevantCabinetObject(_ object: NSManagedObject) -> Bool {
        switch object {
        case is MedicinePackage, is Medicine, is Therapy, is Dose, is Stock, is Log, is Cabinet, is Option, is Package:
            return true
        default:
            return false
        }
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
                        entry.cabinet = cabinet
                        saveContext()
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
            .padding(.top, 18)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
    }

    private var summaryTextView: some View {
        Text(cachedSummaryLines.joined(separator: "\n"))
            .font(.title3.weight(.regular))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
    }

    private func computeSummaryLines() -> [String] {
        viewModel.computeSummaryLines(
            medicines: uniqueMedicines,
            option: options.first,
            pharmacy: PharmacyInfo(
                name: locationVM.pinItem?.title,
                isOpen: locationVM.isLikelyOpen,
                distanceText: locationVM.distanceString
            )
        )
    }

    private var uniqueMedicines: [Medicine] {
        var seen = Set<NSManagedObjectID>()
        return medicinePackages.compactMap { entry -> Medicine? in
            guard !entry.isDeleted, entry.managedObjectContext != nil else { return nil }
            let id = entry.medicine.objectID
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
            cabinets: Array(cabinets)
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
                        top: 14,
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

        if !viewState.favoriteEntries.isEmpty {
            Section(header: sectionHeader("Preferiti")) {
                ForEach(viewState.favoriteEntries, id: \.id) { entry in
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
            let showOtherMedicinesHeader = !(viewState.favoriteEntries.isEmpty && viewState.cabinetEntries.isEmpty)
            if showOtherMedicinesHeader {
                Section(header: sectionHeader("Altri medicinali")) {
                    ForEach(viewState.otherMedicineEntries, id: \.id) { entry in
                        shelfRow(for: entry, orderedEntriesByCabinetID: viewState.orderedEntriesByCabinetID)
                    }
                }
                .listSectionSeparator(.hidden)
            } else {
                Section {
                    ForEach(viewState.otherMedicineEntries, id: \.id) { entry in
                        shelfRow(for: entry, orderedEntriesByCabinetID: viewState.orderedEntriesByCabinetID)
                    }
                }
                .listSectionSeparator(.hidden)
            }
        }
    }

    private func shelfSections(from shelfState: CabinetViewModel.ShelfViewState) -> ShelfViewState {
        var favoriteEntries: [CabinetViewModel.ShelfEntry] = []
        var cabinetEntries: [CabinetViewModel.ShelfEntry] = []
        var otherMedicineEntries: [CabinetViewModel.ShelfEntry] = []
        for entry in shelfState.entries {
            if isFavoriteEntry(entry) {
                favoriteEntries.append(entry)
            } else if case .cabinet = entry.kind {
                cabinetEntries.append(entry)
            } else if case .medicinePackage = entry.kind {
                otherMedicineEntries.append(entry)
            }
        }
        return ShelfViewState(
            favoriteEntries: favoriteEntries,
            cabinetEntries: cabinetEntries,
            otherMedicineEntries: otherMedicineEntries,
            orderedEntriesByCabinetID: shelfState.orderedEntriesByCabinetID
        )
    }

    @ViewBuilder
    private func shelfRow(
        for entry: CabinetViewModel.ShelfEntry,
        orderedEntriesByCabinetID: [NSManagedObjectID: [MedicinePackage]]
    ) -> some View {
        switch entry.kind {
        case .cabinet(let cabinet):
            cabinetRow(
                for: cabinet,
                entries: orderedEntriesByCabinetID[cabinet.objectID] ?? []
            )
        case .medicinePackage(let entry):
            row(for: entry)
        }
    }

    private func isFavoriteEntry(_ entry: CabinetViewModel.ShelfEntry) -> Bool {
        switch entry.kind {
        case .cabinet(let cabinet):
            return favoritesStore.isFavorite(cabinet)
        case .medicinePackage(let entry):
            return favoritesStore.isFavorite(entry)
        }
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
        let cabinet = Cabinet(context: managedObjectContext)
        cabinet.id = UUID()
        cabinet.name = name
        cabinet.created_at = Date()
        saveContext()
        newCabinetName = ""
    }

    private func saveContext() {
        try? managedObjectContext.save()
    }

    private func row(for entry: MedicinePackage) -> some View {
        let rowSnapshot = rowSnapshotsByEntryID[entry.objectID]
        let shouldShowRx = rowSnapshot?.shouldShowPrescription ?? viewModel.shouldShowPrescriptionAction(for: entry)
        return MedicineSwipeRow(
            entry: entry,
            isSelected: viewModel.selectedEntries.contains(entry),
            isInSelectionMode: viewModel.isSelecting,
            shouldShowPrescription: shouldShowRx,
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
        .accessibilityIdentifier("MedicineRow_\(entry.objectID)")
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

    private func cabinetRow(for cabinet: Cabinet, entries: [MedicinePackage]) -> some View {
        let isFavoriteCabinet = favoritesStore.isFavorite(cabinet)
        return Button {
            activeCabinetID = cabinet.objectID
        } label: {
            CabinetCardView(cabinet: cabinet)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            NavigationLink(
                destination: CabinetDetailView(cabinet: cabinet, entries: entries, viewModel: viewModel),
                isActive: Binding(
                    get: { activeCabinetID == cabinet.objectID },
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
                    systemImage: isFavoriteCabinet ? "heart.fill" : "heart"
                )
            }
            .tint(isFavoriteCabinet ? .red : .pink)
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
