import SwiftUI

/// Dettaglio di un cabinet con elenco dei medicinali contenuti.
struct CabinetDetailView: View {
    private struct EntrySelection: Identifiable {
        let id: UUID
    }

    private struct DetailRow: Identifiable {
        let entry: MedicinePackage

        var id: UUID { entry.id }
    }

    let cabinet: Cabinet
    let entries: [MedicinePackage]
    @ObservedObject var viewModel: CabinetViewModel
    @EnvironmentObject private var appDataStore: AppDataStore
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var options: [Option] = []
    @State private var cabinets: [Cabinet] = []
    
    @State private var selectedEntrySelection: EntrySelection?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.75)
    @State private var missedDoseSheet: MissedDoseSheetState?
    @State private var entryToMoveSelection: EntrySelection?
    @State private var isDeleteDialogPresented = false
    @State private var isMoveCabinetSheetPresented = false
    @State private var hasStartedObservation = false
    
    var body: some View {
        let rows = buildRows()
        
        List {
            ForEach(rows) { item in
                row(for: item.entry)
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowSeparator(.hidden, edges: .all)
        .listSectionSpacingIfAvailable(4)
        .listRowSpacing(8)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .navigationTitle(cabinet.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.automatic, for: .navigationBar)
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
                    cabinets: cabinets,
                    onSelect: { cabinet in
                        do {
                            try appDataStore.provider.medicines.moveEntry(
                                entryId: entry.id,
                                toCabinet: cabinet?.id
                            )
                        } catch {
                            // Keep behavior unchanged: ignore persistence errors in move flow.
                        }
                    }
                )
                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
            }
        }
        .sheet(item: $missedDoseSheet) { state in
            MissedDoseIntakeSheet(candidate: state.candidate) { takenAt, nextAction in
                let didRecord = appDataStore.provider.medicines.recordMissedDoseIntake(
                    candidate: state.candidate,
                    takenAt: takenAt,
                    nextAction: nextAction,
                    operationId: state.operationId
                )
                if let key = state.operationKey {
                    handleOperationResult(didRecord, key: key)
                }
            }
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
        .task {
            guard !hasStartedObservation else { return }
            hasStartedObservation = true
            reloadFetchedState()
            for await _ in appDataStore.provider.observe(
                scopes: [.medicines, .therapies, .logs, .stocks, .cabinets, .options]
            ) {
                reloadFetchedState()
            }
        }
    }

    private func buildRows() -> [DetailRow] {
        let valid = entries.filter { !$0.isDeleted }
        return viewModel.sortedEntries(
            in: cabinet,
            entries: valid,
            option: options.first,
            favoriteMedicineIDs: favoritesStore.favoriteMedicineIDs
        )
            .map { DetailRow(entry: $0) }
    }
    
    private func row(for entry: MedicinePackage) -> some View {
        let isSelected = viewModel.selectedEntryIDs.contains(entry.id)
        let shouldShowRx = shouldShowPrescriptionAction(for: entry)
        return MedicineSwipeRow(
            entry: entry,
            isSelected: isSelected,
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
            onMarkTaken: {
                beginMarkTaken(for: entry)
            },
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
            subtitleMode: .activeTherapies
        )
        .listRowSeparator(.hidden, edges: .all)
        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
    }

    private func beginMarkTaken(for entry: MedicinePackage) {
        guard hasSufficientStockForIntake(entry) else { return }

        let token = operationToken(for: .intake, entry: entry)
        if let candidate = appDataStore.provider.medicines.missedDoseCandidate(
            medicine: entry.medicine,
            package: entry.package,
            now: Date()
        ) {
            missedDoseSheet = MissedDoseSheetState(
                candidate: candidate,
                operationId: token.id,
                operationKey: token.key
            )
            return
        }

        let didRecord = appDataStore.provider.medicines.recordIntake(
            medicine: entry.medicine,
            package: entry.package,
            medicinePackage: entry,
            operationId: token.id
        )
        handleOperationResult(didRecord, key: token.key)
    }

    private func hasSufficientStockForIntake(_ entry: MedicinePackage) -> Bool {
        appDataStore.provider.medicines.hasSufficientStockForIntake(entryId: entry.id)
    }

    private func currentEntry(id: UUID) -> MedicinePackage? {
        entries.first { $0.id == id && !$0.isDeleted }
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

    private func handleOperationResult(_ didSucceed: Bool, key: OperationKey) {
        if didSucceed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                OperationIdProvider.shared.clear(key)
            }
        } else {
            OperationIdProvider.shared.clear(key)
        }
    }
    
    private var moveTargets: [Cabinet] {
        cabinets.filter { $0.id != cabinet.id }
    }

    private func deleteCabinet(movingMedicinesTo target: Cabinet?) {
        isMoveCabinetSheetPresented = false
        do {
            try appDataStore.provider.medicines.deleteCabinet(
                cabinetId: cabinet.id,
                moveToCabinetId: target?.id
            )
            dismiss()
        } catch {
            print("Errore eliminazione armadietto: \(error)")
        }
    }

    private func reloadFetchedState() {
        do {
            let snapshot = try appDataStore.provider.medicines.fetchCabinetSnapshot()
            options = snapshot.options
            cabinets = snapshot.cabinets
        } catch {
            options = []
            cabinets = []
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
                                Text("Armadietto")
                                Text("Nessun armadietto")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(cabinets, id: \.id) { cabinet in
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
