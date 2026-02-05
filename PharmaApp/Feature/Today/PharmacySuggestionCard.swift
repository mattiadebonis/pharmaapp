import SwiftUI

struct PharmacySuggestionCard<MapPreview: View, RouteButtons: View>: View {
    let isClosed: Bool
    let cornerRadius: CGFloat
    let mapPreview: () -> MapPreview
    let routeButtons: () -> RouteButtons

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isClosed {
                routeButtons()
            } else {
                Text("Riprova più tardi o spostati di qualche centinaio di metri.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }
}
