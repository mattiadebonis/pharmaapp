import SwiftUI
import Code39

struct TesseraSanitariaCard<FullScreenContent: View>: View {
    let codice: String?
    let cornerRadius: CGFloat
    @Binding var showFullScreen: Bool
    let fullScreenContent: () -> FullScreenContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.22, green: 0.34, blue: 0.62))
                Text("Tessera sanitaria")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
            }
            if let codice {
                Code39View(codice)
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .accessibilityLabel("Barcode Tessera Sanitaria")
                    .accessibilityValue(codice)
                Text(codice)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("Aggiungi la tessera sanitaria dalle Opzioni.")
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
        .contentShape(Rectangle())
        .onTapGesture {
            if codice != nil {
                showFullScreen = true
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            fullScreenContent()
        }
    }
}
