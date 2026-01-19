import SwiftUI
import CoreData

/// Vista dedicata al tab "Armadietto" (ex ramo medicines di FeedView)
struct CabinetView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.managedObjectContext) private var managedObjectContext
    @StateObject private var viewModel = CabinetViewModel()

    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    private var medicines: FetchedResults<Medicine>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractLogs())
    private var logs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Cabinet.extractCabinets())
    private var cabinets: FetchedResults<Cabinet>

    @State private var selectedMedicine: Medicine?
    @State private var activeCabinetID: NSManagedObjectID?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.66)
    @State private var medicineToMove: Medicine?
    @State private var isNewCabinetPresented = false
    @State private var newCabinetName = ""

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
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) { // medium spacing
                        Button {
                            appVM.isSettingsPresented = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Color.accentColor)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ToolbarIconButtonStyle())
                        .accessibilityLabel("Impostazioni")

                        Button {
                            isNewCabinetPresented = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "cross.case")
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .offset(x: 6, y: -6)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ToolbarIconButtonStyle())
                        .accessibilityLabel("Nuovo armadietto")
                    }
                }
            }
    }

    private var cabinetListWithNewCabinetSheet: some View {
        cabinetListWithDetailSheet
            .sheet(isPresented: $isNewCabinetPresented, onDismiss: { newCabinetName = "" }) {
                newCabinetSheet
            }
    }

    private var cabinetListWithDetailSheet: some View {
        cabinetListStyled
            .id(logs.count)
            .sheet(isPresented: isDetailSheetPresented) {
                medicineDetailSheet
            }
            .sheet(item: $medicineToMove) { medicine in
                MoveToCabinetSheet(
                    medicine: medicine,
                    cabinets: Array(cabinets),
                    onSelect: { cabinet in
                        medicine.cabinet = cabinet
                        saveContext()
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .onChange(of: selectedMedicine) { newValue in
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
            .listSectionSpacing(4)
            .listRowSpacing(12)
            .listStyle(.plain)
            .padding(.top, 16)
            .padding(.leading, 5)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
    }

    private var cabinetListView: AnyView {
        let entries = viewModel.shelfEntries(
            medicines: Array(medicines),
            logs: Array(logs),
            option: options.first,
            cabinets: Array(cabinets)
        )

        return AnyView(List {
            if appVM.suggestNearestPharmacies {
                Section {
                    smartBannerCard
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 16, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                .listSectionSeparator(.hidden)
            }

            ForEach(entries) { entry in
                switch entry.kind {
                case .medicine(let med):
                    row(for: med)
                case .cabinet(let cabinet):
                    let meds = viewModel.sortedMedicines(in: cabinet)
                    ZStack {
                        Button {
                            activeCabinetID = cabinet.objectID
                        } label: {
                            CabinetCardView(
                                cabinet: cabinet,
                                medicineCount: meds.count
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(
                            destination: CabinetDetailView(cabinet: cabinet, medicines: meds, viewModel: viewModel),
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
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden, edges: .all)
                    .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                }
            }
        })
    }

    // MARK: - Helpers
    private var isDetailSheetPresented: Binding<Bool> {
        Binding(
            get: { selectedMedicine != nil },
            set: { newValue in
                if !newValue { selectedMedicine = nil }
            }
        )
    }

    @ViewBuilder
    private var medicineDetailSheet: some View {
        if let medicine = selectedMedicine {
            if let package = viewModel.package(for: medicine) {
                MedicineDetailView(
                    medicine: medicine,
                    package: package
                )
                .presentationDetents([.fraction(0.66), .large], selection: $detailSheetDetent)
                .presentationDragIndicator(.visible)
            } else {
                VStack(spacing: 12) {
                    Text("Completa i dati del medicinale")
                        .font(.headline)
                    Text("Aggiungi una confezione dalla schermata dettaglio per utilizzare le funzioni avanzate.")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .presentationDetents([.medium])
            }
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

    private func row(for medicine: Medicine) -> some View {
        let shouldShowRx = viewModel.shouldShowPrescriptionAction(for: medicine)
        return MedicineSwipeRow(
            medicine: medicine,
            isSelected: viewModel.selectedMedicines.contains(medicine),
            isInSelectionMode: viewModel.isSelecting,
            shouldShowPrescription: shouldShowRx,
            onTap: {
                if viewModel.isSelecting {
                    viewModel.toggleSelection(for: medicine)
                } else {
                    selectedMedicine = medicine
                }
            },
            onLongPress: {
                selectedMedicine = medicine
                Haptics.impact(.medium)
            },
            onToggleSelection: { viewModel.toggleSelection(for: medicine) },
            onEnterSelection: { viewModel.enterSelectionMode(with: medicine) },
            onMarkTaken: { viewModel.actionService.markAsTaken(for: medicine) },
            onMarkPurchased: { viewModel.actionService.markAsPurchased(for: medicine) },
            onRequestPrescription: shouldShowRx ? { viewModel.actionService.requestPrescription(for: medicine) } : nil,
            onMove: { medicineToMove = medicine }
        )
        .accessibilityIdentifier("MedicineRow_\(medicine.objectID)")
        .listRowSeparator(.hidden, edges: .all)
        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
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
        if medicine.hasNewPrescritpionRequest() { return false }
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
