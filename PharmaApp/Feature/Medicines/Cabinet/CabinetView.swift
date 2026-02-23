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
    }

    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.managedObjectContext) private var managedObjectContext
    @StateObject private var viewModel = CabinetViewModel()
    @StateObject private var locationVM = LocationSearchViewModel()

    @FetchRequest(fetchRequest: MedicinePackage.extractEntries())
    private var medicinePackages: FetchedResults<MedicinePackage>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractRecentLogs(days: 7))
    private var logs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Cabinet.extractCabinets())
    private var cabinets: FetchedResults<Cabinet>

    @State private var activeCabinetID: NSManagedObjectID?
    @State private var entryToMove: MedicinePackage?
    @State private var isNewCabinetPresented = false
    @State private var newCabinetName = ""
    @State private var isSearchPresented = false
    @State private var isProfilePresented = false
    @State private var catalogSelection: CatalogSelection?
    @State private var pendingCatalogSelection: CatalogSelection?
    @State private var selectedEntry: MedicinePackage?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.75)
    @State private var cachedSummaryLines: [String] = ["Tutto sotto controllo"]
    @State private var syncWorkItem: DispatchWorkItem?

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
            .onAppear {
                locationVM.ensureStarted()
                recomputeSummaryLines()
                syncSummaryToWidgetDebounced()
            }
            .onChange(of: medicinePackages.count) { _ in
                recomputeSummaryLines()
                syncSummaryToWidgetDebounced()
            }
            .onChange(of: logs.count) { _ in
                recomputeSummaryLines()
                syncSummaryToWidgetDebounced()
            }
    }

    private func recomputeSummaryLines() {
        cachedSummaryLines = computeSummaryLines()
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

    private var cabinetListWithNewCabinetSheet: some View {
        cabinetListWithDetailSheet
            .sheet(isPresented: $isNewCabinetPresented, onDismiss: { newCabinetName = "" }) {
                newCabinetSheet
            }
            .sheet(isPresented: $isSearchPresented, onDismiss: {
                if let pending = pendingCatalogSelection {
                    pendingCatalogSelection = nil
                    DispatchQueue.main.async {
                        catalogSelection = pending
                    }
                }
            }) {
                NavigationStack {
                    CatalogSearchScreen { selection in
                        pendingCatalogSelection = selection
                        isSearchPresented = false
                    }
                }
            }
            .sheet(isPresented: $isProfilePresented) {
                NavigationStack {
                    ProfileView()
                }
            }
            .sheet(item: $catalogSelection) { selection in
                MedicineWizardView(prefill: selection) {
                    catalogSelection = nil
                }
                .environmentObject(appVM)
                .environment(\.managedObjectContext, managedObjectContext)
                .presentationDetents([.fraction(0.5), .large])
            }
    }

    private var cabinetListWithDetailSheet: some View {
        cabinetListStyled
            .sheet(isPresented: Binding(
                get: { selectedEntry != nil },
                set: { newValue in if !newValue { selectedEntry = nil } }
            )) {
                if let entry = selectedEntry {
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

    private func camelCaseName(_ text: String) -> String {
        text.lowercased().split(separator: " ").map { part in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    private func computeSummaryLines() -> [String] {
        let medicines = uniqueMedicines
        guard let option = options.first else {
            return ["Tutto sotto controllo"]
        }
        let recurrence = RecurrenceManager.shared

        let lowStock = medicines.filter { $0.isInEsaurimento(option: option, recurrenceManager: recurrence) }

        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let justBeforeToday = startOfToday.addingTimeInterval(-1)
        let missedDoses = medicines.filter { medicine in
            guard let firstDoseToday = medicine.nextIntakeDate(from: justBeforeToday, recurrenceManager: recurrence) else { return false }
            return calendar.isDateInToday(firstDoseToday)
                && firstDoseToday < now
                && !medicine.hasIntakeLoggedToday(calendar: calendar)
        }

        let stockOk = lowStock.isEmpty
        let therapyOk = missedDoses.isEmpty

        if stockOk && therapyOk {
            return ["Tutto sotto controllo"]
        }

        var lines: [String] = []

        if stockOk {
            lines.append("Scorte a posto")
        } else {
            let names = lowStock.prefix(3).map { camelCaseName($0.nome) }
            let label = names.joined(separator: ", ")
            if lowStock.count > 3 {
                lines.append("\(label) e altri \(lowStock.count - 3) in esaurimento")
            } else {
                lines.append("\(label) in esaurimento")
            }
            if let pharmacyName = locationVM.pinItem?.title {
                var pharmacyLine = pharmacyName
                if let open = locationVM.isLikelyOpen {
                    pharmacyLine += open ? " · aperta" : " · chiusa"
                }
                if let distance = locationVM.distanceString {
                    pharmacyLine += " · \(distance)"
                }
                lines.append(pharmacyLine)
            }
        }

        if therapyOk {
            lines.append("Terapie in regola")
        } else {
            let names = missedDoses.prefix(3).map { camelCaseName($0.nome) }
            let label = names.joined(separator: ", ")
            if missedDoses.count > 3 {
                lines.append("\(label) e altri \(missedDoses.count - 3) da assumere")
            } else {
                lines.append("\(label) da assumere")
            }
        }

        return lines
    }

    private var uniqueMedicines: [Medicine] {
        var seen = Set<NSManagedObjectID>()
        return medicinePackages.compactMap { entry -> Medicine? in
            let id = entry.medicine.objectID
            guard seen.insert(id).inserted else { return nil }
            return entry.medicine
        }
    }

    private var cabinetListView: AnyView {
        let viewState = buildShelfViewState()
        return AnyView(List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(cachedSummaryLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 24, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listSectionSeparator(.hidden)

            if appVM.suggestNearestPharmacies {
                Section {
                    smartBannerCard
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 16, trailing: 20))
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
        })
    }

    private func buildShelfViewState() -> ShelfViewState {
        let shelfState = viewModel.shelfViewState(
            entries: Array(medicinePackages),
            logs: Array(logs),
            option: options.first,
            cabinets: Array(cabinets)
        )
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
        .padding(.horizontal, 24)
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
        let shouldShowRx = viewModel.shouldShowPrescriptionAction(for: entry)
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
                let opId = operationToken(for: .intake, entry: entry).id
                viewModel.actionService.markAsTaken(for: entry, operationId: opId)
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
            subtitleMode: .activeTherapies
        )
        .accessibilityIdentifier("MedicineRow_\(entry.objectID)")
        .listRowSeparator(.hidden, edges: .all)
        .listRowInsets(EdgeInsets(top: 1, leading: 24, bottom: 1, trailing: 24))
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
        .listRowInsets(EdgeInsets(top: 1, leading: 24, bottom: 1, trailing: 24))
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

    // MARK: - Prescription helpers reused
    private func needsPrescriptionBeforePurchase(_ medicine: Medicine, recurrenceManager: RecurrenceManager) -> Bool {
        guard medicine.obbligo_ricetta else { return false }
        if medicine.hasEffectivePrescriptionReceived() { return false }
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
            let threshold = Double(medicine.stockThreshold(option: options.first))
            return days < threshold
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            return remaining <= medicine.stockThreshold(option: options.first)
        }
        return false
    }
}

private struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .overlay(
                Circle()
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear)
            )
    }
}
