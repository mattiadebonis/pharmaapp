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
    @State private var isDeleteDialogPresented = false
    @State private var isMoveCabinetSheetPresented = false
    
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
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowSeparator(.hidden, edges: .all)
        .listSectionSpacing(4)
        .listRowSpacing(8)
        .scrollContentBackground(.hidden)
        .navigationTitle(cabinet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isDeleteDialogPresented = true
                    } label: {
                        Label("Elimina armadietto", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .contentShape(Rectangle())
            }
        }
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
                    medicine.in_cabinet = cabinet != nil
                    saveContext()
                }
            )
            .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
        .sheet(isPresented: $isMoveCabinetSheetPresented) {
            MoveCabinetSelectionSheet(
                cabinets: moveTargets,
                onSelect: { target in
                    deleteCabinet(movingMedicinesTo: target)
                }
            )
        }
        .alert("Elimina armadietto", isPresented: $isDeleteDialogPresented) {
            Button("Sposta medicinali in un altro armadietto") {
                isMoveCabinetSheetPresented = true
            }
            Button("Rimuovi medicinali dall'armadietto", role: .destructive) {
                deleteCabinet(movingMedicinesTo: nil)
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Cosa vuoi fare con i medicinali di questo armadietto?")
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
        .listRowSeparator(.hidden, edges: .all)
        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
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

    private var moveTargets: [Cabinet] {
        cabinets.filter { $0.objectID != cabinet.objectID }
    }

    private func deleteCabinet(movingMedicinesTo target: Cabinet?) {
        isMoveCabinetSheetPresented = false
        let context = cabinet.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let medicinesToUpdate = Array(cabinet.medicines)
        for medicine in medicinesToUpdate {
            medicine.cabinet = target
            medicine.in_cabinet = target != nil
        }
        context.delete(cabinet)
        do {
            try context.save()
            dismiss()
        } catch {
            print("Errore eliminazione armadietto: \(error)")
        }
    }
}

private struct MoveCabinetSelectionSheet: View {
    let cabinets: [Cabinet]
    var onSelect: (Cabinet?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if cabinets.isEmpty {
                        Button {
                            onSelect(nil)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Armadio dei farmaci")
                                Text("Nessun armadietto")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(cabinets, id: \.objectID) { cabinet in
                        Button {
                            onSelect(cabinet)
                            dismiss()
                        } label: {
                            Text(cabinet.name)
                        }
                    }
                } header: {
                    Text("Sposta in")
                }
            }
            .navigationTitle("Sposta medicinali")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
