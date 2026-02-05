import SwiftUI
import CoreData

/// Vista dedicata al tab "Armadietto" (ex ramo medicines di FeedView)
struct CabinetView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.managedObjectContext) private var managedObjectContext
    @StateObject private var viewModel = CabinetViewModel()

    @FetchRequest(fetchRequest: MedicinePackage.extractEntries())
    private var medicinePackages: FetchedResults<MedicinePackage>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractLogs())
    private var logs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Cabinet.extractCabinets())
    private var cabinets: FetchedResults<Cabinet>

    @State private var selectedEntry: MedicinePackage?
    @State private var activeCabinetID: NSManagedObjectID?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.66)
    @State private var entryToMove: MedicinePackage?
    @State private var isNewCabinetPresented = false
    @State private var newCabinetName = ""
    @State private var isSearchPresented = false
    @State private var catalogSelection: CatalogSelection?
    @State private var expandedCabinetIDs: Set<NSManagedObjectID> = []
    @State private var visibleCabinetIDs: Set<NSManagedObjectID> = []

    var body: some View {
        cabinetRootView
    }

    private var cabinetRootView: some View {
        cabinetListWithNavigation
    }

    private var cabinetListWithNavigation: some View {
        cabinetListWithNewCabinetSheet
            .navigationTitle("Armadio dei farmaci")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appVM.isProfilePresented = true
                    } label: {
                        Image(systemName: "person")
                    }
                    .accessibilityLabel("Profilo")
                    .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isNewCabinetPresented = true
                        } label: {
                            Label("Nuovo armadietto", systemImage: "cross.case.fill")
                        }

                        Button {
                            isSearchPresented = true
                        } label: {
                            Label("Nuovo farmaco", systemImage: "pills")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Aggiungi")
                    .foregroundStyle(.primary)
                }
            }
    }

    private var cabinetListWithNewCabinetSheet: some View {
        cabinetListWithDetailSheet
            .sheet(isPresented: $isNewCabinetPresented, onDismiss: { newCabinetName = "" }) {
                newCabinetSheet
            }
            .sheet(isPresented: $isSearchPresented) {
                NavigationStack {
                    CatalogSearchScreen { selection in
                        isSearchPresented = false
                        DispatchQueue.main.async {
                            catalogSelection = selection
                        }
                    }
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
            .id(logs.count)
            .sheet(isPresented: isDetailSheetPresented) {
                medicineDetailSheet
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
            .onChange(of: selectedEntry) { newValue in
                if newValue == nil {
                    viewModel.clearSelection()
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
            .padding(.leading, 5)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
    }

    private var cabinetListView: AnyView {
        let entries = viewModel.shelfEntries(
            entries: Array(medicinePackages),
            logs: Array(logs),
            option: options.first,
            cabinets: Array(cabinets)
        )
        let favoriteEntries = entries.filter { isFavoriteEntry($0) }
        let otherEntries = entries.filter { !isFavoriteEntry($0) }
        return AnyView(List {
            if appVM.suggestNearestPharmacies {
                Section {
                    smartBannerCard
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 16, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                .listSectionSeparator(.hidden)
            }

            if !favoriteEntries.isEmpty {
                Section(header: sectionHeader("Preferiti")) {
                    ForEach(favoriteEntries, id: \.id) { entry in
                        shelfRow(for: entry)
                    }
                }
                .listSectionSeparator(.hidden)
            }

            ForEach(otherEntries, id: \.id) { entry in
                shelfRow(for: entry)
            }
        })
    }

    @ViewBuilder
    private func shelfRow(for entry: CabinetViewModel.ShelfEntry) -> some View {
        switch entry.kind {
        case .cabinet(let cabinet):
            cabinetRow(for: cabinet)
            cabinetExpandedRows(for: cabinet)
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
        .padding(.leading, 4)
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
    private var isDetailSheetPresented: Binding<Bool> {
        Binding(
            get: { selectedEntry != nil },
            set: { newValue in
                if !newValue { selectedEntry = nil }
            }
        )
    }

    @ViewBuilder
    private var medicineDetailSheet: some View {
        if let entry = selectedEntry {
            MedicineDetailView(
                medicine: entry.medicine,
                package: entry.package,
                medicinePackage: entry
            )
            .presentationDetents([.fraction(0.66), .large], selection: $detailSheetDetent)
            .presentationDragIndicator(.visible)
        } else {
            EmptyView()
        }
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
        let cabinet = Cabinet(context: managedObjectContext)
        cabinet.id = UUID()
        cabinet.name = name
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
            onMove: { entryToMove = entry }
        )
        .accessibilityIdentifier("MedicineRow_\(entry.objectID)")
        .listRowSeparator(.hidden, edges: .all)
        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
    }

    private func cabinetRow(for cabinet: Cabinet) -> some View {
        let entries = viewModel.sortedEntries(
            in: cabinet,
            entries: Array(medicinePackages),
            logs: Array(logs),
            option: options.first
        )

        let isFavoriteCabinet = favoritesStore.isFavorite(cabinet)
        let isExpanded = expandedCabinetIDs.contains(cabinet.objectID)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    activeCabinetID = cabinet.objectID
                } label: {
                    CabinetCardView(cabinet: cabinet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    toggleCabinetExpansion(for: cabinet)
                } label: {
                    cabinetExpandControl(count: entries.count, isExpanded: isExpanded)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Comprimi armadietto" : "Espandi armadietto")
            }
        }
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
        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
    }

    private func toggleCabinetExpansion(for cabinet: Cabinet) {
        let id = cabinet.objectID
        let fadeDuration = 0.28
        let revealDelay = 0.08

        if expandedCabinetIDs.contains(id) {
            expandedCabinetIDs.remove(id)
            withAnimation(.easeInOut(duration: fadeDuration)) {
                visibleCabinetIDs.remove(id)
            }
        } else {
            expandedCabinetIDs.insert(id)
            visibleCabinetIDs.remove(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
                guard expandedCabinetIDs.contains(id) else { return }
                withAnimation(.easeInOut(duration: fadeDuration)) {
                    visibleCabinetIDs.insert(id)
                }
            }
        }
    }

    private func cabinetExpandControl(count: Int, isExpanded: Bool) -> some View {
        HStack(spacing: 14) {
            Text("\(count)")
                .font(.system(size: 16, weight: .regular))
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .regular))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .foregroundStyle(Color.primary.opacity(0.45))
        .padding(.top, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cabinetExpandedRows(for cabinet: Cabinet) -> some View {
        let id = cabinet.objectID
        if expandedCabinetIDs.contains(id) {
            let entries = viewModel.sortedEntries(
                in: cabinet,
                entries: Array(medicinePackages),
                logs: Array(logs),
                option: options.first
            )
            let isVisible = visibleCabinetIDs.contains(id)

            if entries.isEmpty {
                cabinetExpandedEmptyRow()
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.28), value: isVisible)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.objectID) { index, entry in
                    cabinetExpandedRow(for: entry, isFirst: index == 0)
                        .opacity(isVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.28), value: isVisible)
                }
            }
        } else {
            EmptyView()
        }
    }

    private func cabinetExpandedRow(for entry: MedicinePackage, isFirst: Bool) -> some View {
        let shouldShowRx = viewModel.shouldShowPrescriptionAction(for: entry)
        let isFavorite = favoritesStore.isFavorite(entry)
        let isSelected = viewModel.selectedEntries.contains(entry)
        return cabinetExpandedReview(for: entry)
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.isSelecting {
                    viewModel.toggleSelection(for: entry)
                } else {
                    selectedEntry = entry
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    entryToMove = entry
                } label: {
                    swipeLabel("Sposta", systemImage: "tray.and.arrow.up.fill")
                }
                .tint(.indigo)

                Button {
                    let opId = operationToken(for: .intake, entry: entry).id
                    viewModel.actionService.markAsTaken(for: entry, operationId: opId)
                } label: {
                    swipeLabel("Assunto", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)

                Button {
                    let token = operationToken(for: .purchase, entry: entry)
                    let log = viewModel.actionService.markAsPurchased(for: entry, operationId: token.id)
                    handleOperationResult(log, key: token.key)
                } label: {
                    swipeLabel("Acquistato", systemImage: "cart.fill")
                }
                .tint(.blue)

                if shouldShowRx {
                    Button {
                        let token = operationToken(for: .prescriptionRequest, entry: entry)
                        let log = viewModel.actionService.requestPrescription(for: entry, operationId: token.id)
                        handleOperationResult(log, key: token.key)
                    } label: {
                        swipeLabel("Ricetta", systemImage: "doc.text.fill")
                    }
                    .tint(.orange)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    favoritesStore.toggleFavorite(entry)
                } label: {
                    swipeLabel(
                        isFavorite ? "Rimuovi preferiti" : "Preferito",
                        systemImage: isFavorite ? "heart.fill" : "heart"
                    )
                }
                .tint(isFavorite ? .red : .pink)

                Button {
                    if viewModel.isSelecting {
                        viewModel.toggleSelection(for: entry)
                    } else {
                        viewModel.enterSelectionMode(with: entry)
                    }
                } label: {
                    swipeLabel(
                        isSelected ? "Deseleziona" : "Seleziona",
                        systemImage: isSelected ? "minus.circle" : "plus.circle"
                    )
                }
                .tint(.accentColor)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden, edges: .all)
            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
            .padding(.top, isFirst ? -7 : 0)
    }

    private func cabinetExpandedEmptyRow() -> some View {
        Text("Nessun farmaco")
            .font(medicineReviewSubtitleFont)
            .foregroundStyle(medicineReviewSubtitleColor)
            .padding(.leading, CabinetCardView.textIndent)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden, edges: .all)
            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
            .padding(.top, -7)
    }

    private func cabinetExpandedReview(for entry: MedicinePackage) -> some View {
        let subtitle = makeMedicineSubtitle(medicine: entry.medicine, medicinePackage: entry, now: Date())
        return HStack(alignment: .top, spacing: medicineReviewIconSpacing) {
            medicineReviewIcon
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(formattedMedicineName(entry))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let dosage = medicineDosageLabel(entry) {
                        Text(" \(dosage)")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !subtitle.line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle.line1)
                        .font(medicineReviewSubtitleFont)
                        .foregroundStyle(medicineReviewSubtitleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                line2View(for: subtitle.line2)
            }
        }
        .padding(.leading, CabinetCardView.textIndent)
    }

    @ViewBuilder
    private func line2View(for line: String) -> some View {
        let lowPrefix = "Scorte basse"
        let emptyPrefix = "Scorte finite"

        if line.hasPrefix(emptyPrefix) {
            let suffix = String(line.dropFirst(emptyPrefix.count))
            (Text(emptyPrefix).foregroundColor(.red) + Text(suffix).foregroundColor(medicineReviewSubtitleColor))
                .font(medicineReviewSubtitleFont)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if line.hasPrefix(lowPrefix) {
            Text(line)
                .font(medicineReviewSubtitleFont)
                .foregroundColor(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(line)
                .font(medicineReviewSubtitleFont)
                .foregroundColor(medicineReviewSubtitleColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var medicineReviewSubtitleColor: Color {
        Color.primary.opacity(0.45)
    }

    private var medicineReviewSubtitleFont: Font {
        Font.custom("SFProDisplay-CondensedLight", size: 15)
    }

    private var medicineReviewIcon: some View {
        Image(systemName: "pill")
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Color.accentColor)
            .frame(width: medicineReviewIconSize, height: medicineReviewIconSize, alignment: .center)
    }

    private var medicineReviewIconSize: CGFloat { 22 }

    private var medicineReviewIconSpacing: CGFloat { 8 }

    private func formattedMedicineName(_ entry: MedicinePackage) -> String {
        let raw = entry.medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = raw.isEmpty ? "Medicinale" : raw
        return camelCase(base)
    }

    private func medicineDosageLabel(_ entry: MedicinePackage) -> String? {
        packageDosageLabel(entry.package)
    }

    private func packageDosageLabel(_ pkg: Package) -> String? {
        guard pkg.valore > 0 else { return nil }
        let unit = pkg.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? "\(pkg.valore)" : "\(pkg.valore) \(unit)"
    }

    private func camelCase(_ text: String) -> String {
        let lowered = text.lowercased()
        return lowered
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
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
