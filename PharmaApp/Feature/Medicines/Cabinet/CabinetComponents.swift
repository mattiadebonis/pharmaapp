import SwiftUI
import CoreData

/// Riga con swipe action per i medicinali nell'armadietto.
struct MedicineSwipeRow: View {
    @ObservedObject var entry: MedicinePackage
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
    private var medicine: Medicine { entry.medicine }
    @EnvironmentObject private var favoritesStore: FavoritesStore

    var body: some View {
        MedicineRowView(
            medicine: medicine,
            medicinePackage: entry,
            isSelected: isSelected,
            isInSelectionMode: isInSelectionMode
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture { onLongPress() }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let move = onMove {
                Button {
                    move()
                } label: {
                    swipeLabel("Sposta", systemImage: "tray.and.arrow.up.fill")
                }
                .tint(.indigo)
            }

            Button {
                onMarkTaken()
            } label: {
                swipeLabel("Assunto", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)

            Button {
                onMarkPurchased()
            } label: {
                swipeLabel("Acquistato", systemImage: "cart.fill")
            }
            .tint(.blue)

            if let action = onRequestPrescription, shouldShowPrescription {
                Button {
                    action()
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
                    favoritesLabel,
                    systemImage: favoritesIcon
                )
            }
            .tint(favoritesTint)

            Button {
                if isInSelectionMode {
                    onToggleSelection()
                } else {
                    onEnterSelection()
                }
            } label: {
                swipeLabel(
                    isSelected ? "Deseleziona" : "Seleziona",
                    systemImage: isSelected ? "minus.circle" : "plus.circle"
                )
            }
            .tint(.accentColor)
        }
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

    private var isFavorite: Bool {
        favoritesStore.isFavorite(entry)
    }

    private var favoritesLabel: String {
        isFavorite ? "Rimuovi preferiti" : "Preferito"
    }

    private var favoritesIcon: String {
        isFavorite ? "heart.fill" : "heart"
    }

    private var favoritesTint: Color {
        isFavorite ? .red : .pink
    }
}

/// Sheet semplificato per spostare un medicinale in un armadietto o nell'armadio dei farmaci.
struct MoveToCabinetSheet: View {
    let entry: MedicinePackage
    let cabinets: [Cabinet]
    var onSelect: (Cabinet?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Armadio dei farmaci")
                                Text("Nessun armadietto")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.cabinet == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    ForEach(Array(cabinets.enumerated()), id: \.element.objectID) { _, cabinet in
                        Button {
                            onSelect(cabinet)
                            dismiss()
                        } label: {
                            HStack {
                                Text(cabinet.displayName)
                                Spacer()
                                if entry.cabinet?.objectID == cabinet.objectID {
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
