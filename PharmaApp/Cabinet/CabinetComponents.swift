import SwiftUI
import CoreData

/// Riga con swipe action per i medicinali nell'armadietto.
struct MedicineSwipeRow: View {
    @ObservedObject var medicine: Medicine
    var isSelected: Bool
    var isInSelectionMode: Bool
    var shouldShowPrescription: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void
    var onToggleSelection: () -> Void
    var onEnterSelection: () -> Void
    var onMarkTaken: () -> Void
    var onMarkPurchased: () -> Void
    var onRequestPrescription: (() -> Void)?
    var onMove: (() -> Void)?

    var body: some View {
        MedicineRowView(
            medicine: medicine,
            isSelected: isSelected,
            isInSelectionMode: isInSelectionMode
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture { onLongPress() }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onMarkTaken()
            } label: {
                Label("Assunto", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)

            Button {
                onMarkPurchased()
            } label: {
                Label("Acquistato", systemImage: "cart.fill")
            }
            .tint(.blue)

            if let action = onRequestPrescription, shouldShowPrescription {
                Button {
                    action()
                } label: {
                    Label("Ricetta", systemImage: "doc.text.fill")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let move = onMove {
                Button {
                    move()
                } label: {
                    Label("Sposta", systemImage: "tray.and.arrow.up.fill")
                }
                .tint(.indigo)
            }

            Button {
                if isInSelectionMode {
                    onToggleSelection()
                } else {
                    onEnterSelection()
                }
            } label: {
                Label(isSelected ? "Deseleziona" : "Seleziona", systemImage: isSelected ? "minus.circle" : "plus.circle")
            }
            .tint(.accentColor)
        }
    }
}

/// Sheet semplificato per spostare un medicinale in un armadietto.
struct MoveToCabinetSheet: View {
    let medicine: Medicine
    let cabinets: [Cabinet]
    var onSelect: (Cabinet) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
            NavigationStack {
            List {
                Section {
                    ForEach(Array(cabinets.enumerated()), id: \.element.objectID) { _, cabinet in
                        Button {
                            onSelect(cabinet)
                            dismiss()
                        } label: {
                            HStack {
                                Text(cabinet.name)
                                Spacer()
                                if medicine.cabinet?.objectID == cabinet.objectID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Sposta in")
                }
            }
            .navigationTitle("Sposta medicinale")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
