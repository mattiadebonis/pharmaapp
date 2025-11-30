import SwiftUI
import CoreData

struct CabinetCardView: View {
    let cabinet: Cabinet
    var medicineCount: Int
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(cabinet.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                Text("\(medicineCount) medicine")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
    
    private var leadingIcon: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28, alignment: .topLeading)
    }
}
