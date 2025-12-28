import SwiftUI
import CoreData

/// Dettaglio di un cabinet con elenco dei medicinali contenuti.
struct CabinetDetailView: View {
    let cabinet: Cabinet
    let medicines: [Medicine]
    @ObservedObject var viewModel: CabinetViewModel
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractLogs()) private var logs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Cabinet.extractCabinets()) private var cabinets: FetchedResults<Cabinet>
    
    @State private var selectedMedicine: Medicine?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.66)
    @State private var medicineToMove: Medicine?
    
    var body: some View {
        let sections = computeSections(for: medicines, logs: Array(logs), option: options.first)
        let rows = sections.purchase.map { ($0, MedicineRowView.RowSection.purchase) }
            + sections.oggi.map { ($0, MedicineRowView.RowSection.tuttoOk) }
            + sections.ok.map { ($0, MedicineRowView.RowSection.tuttoOk) }
        
        List {
            ForEach(rows, id: \.0.objectID) { entry in
                let med = entry.0
                row(for: med)
            }
        }
        .listStyle(.insetGrouped)
        .listRowSeparator(.hidden)
        .scrollContentBackground(.hidden)
        .navigationTitle(cabinet.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { newValue in if !newValue { selectedMedicine = nil } }
        )) {
            if let medicine = selectedMedicine {
                if let package = getPackage(for: medicine) {
                    MedicineDetailView(medicine: medicine, package: package)
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
                    .presentationDetents([PresentationDetent.medium])
                }
            }
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
            .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
    }
    
    private func row(for medicine: Medicine) -> some View {
        let isSelected = viewModel.selectedMedicines.contains(medicine)
        let shouldShowRx = shouldShowPrescriptionAction(for: medicine)
        return MedicineSwipeRow(
            medicine: medicine,
            isSelected: isSelected,
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
    }
    
    private func shouldShowPrescriptionAction(for medicine: Medicine) -> Bool {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        return needsPrescriptionBeforePurchase(medicine, recurrenceManager: rec)
    }
    
    private func getPackage(for medicine: Medicine) -> Package? {
        if let packages = medicine.packages as? Set<Package> {
            return packages.first
        }
        return nil
    }
    
    private func saveContext() {
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
            print("Errore salvataggio: \(error)")
        }
    }
}
