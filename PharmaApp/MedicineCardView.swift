import SwiftUI
import CoreData

/// Reusable card for medicine row styling. Supports tap and optional drop handling (passing a Medicine).
struct MedicineCardView: View {
    let medicine: Medicine
    var isSelected: Bool = false
    var isInSelectionMode: Bool = false
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        MedicineRowView(medicine: medicine, isSelected: isSelected, isInSelectionMode: isInSelectionMode)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }
    }
}
