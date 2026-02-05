import SwiftUI
import CoreData

/// Dettaglio di un cabinet con elenco dei medicinali contenuti.
struct CabinetDetailView: View {
    let cabinet: Cabinet
    let entries: [MedicinePackage]
    @ObservedObject var viewModel: CabinetViewModel
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractLogs()) private var logs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Cabinet.extractCabinets()) private var cabinets: FetchedResults<Cabinet>
    
    @State private var selectedEntry: MedicinePackage?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.66)
    @State private var entryToMove: MedicinePackage?
    @State private var isDeleteDialogPresented = false
    @State private var isMoveCabinetSheetPresented = false
    
    var body: some View {
        let sections = computeSections(for: entries, logs: Array(logs), option: options.first)
        let rows = sections.purchase.map { ($0, MedicineRowView.RowSection.purchase) }
            + sections.oggi.map { ($0, MedicineRowView.RowSection.tuttoOk) }
            + sections.ok.map { ($0, MedicineRowView.RowSection.tuttoOk) }
        
        List {
            ForEach(rows, id: \.0.objectID) { entry in
                let medPackage = entry.0
                row(for: medPackage)
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowSeparator(.hidden, edges: .all)
        .listSectionSpacingIfAvailable(4)
        .listRowSpacing(8)
        .scrollContentBackground(.hidden)
        .navigationTitle(cabinet.displayName)
        .navigationBarTitleDisplayMode(.large)
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
            get: { selectedEntry != nil },
            set: { newValue in if !newValue { selectedEntry = nil } }
        )) {
            if let entry = selectedEntry {
                MedicineDetailView(
                    medicine: entry.medicine,
                    package: entry.package,
                    medicinePackage: entry
                )
                .presentationDetents([.fraction(0.66), .large], selection: $detailSheetDetent)
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
    
    private func row(for entry: MedicinePackage) -> some View {
        let isSelected = viewModel.selectedEntries.contains(entry)
        let shouldShowRx = shouldShowPrescriptionAction(for: entry)
        return MedicineSwipeRow(
            entry: entry,
            isSelected: isSelected,
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
        .listRowSeparator(.hidden, edges: .all)
        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
    }
    
    private func shouldShowPrescriptionAction(for entry: MedicinePackage) -> Bool {
        viewModel.shouldShowPrescriptionAction(for: entry)
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
        let entriesToUpdate = Array(cabinet.medicinePackages ?? [])
        for entry in entriesToUpdate {
            entry.cabinet = target
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
                            Text(cabinet.displayName)
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
