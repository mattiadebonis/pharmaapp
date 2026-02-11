import SwiftUI
import Code39

struct CodiceFiscaleFullscreenView: View {
    let codiceFiscale: String?
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.white
                .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    if let codice = normalizedCodiceFiscale {
                        VStack(spacing: 12) {
                            Code39View(codice)
                                .frame(maxWidth: min(proxy.size.width * 0.92, 700))
                                .frame(height: 140)
                                .accessibilityLabel("Barcode Codice Fiscale")
                                .accessibilityValue(codice)
                            Text(codice)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Aggiungi il codice fiscale dal profilo.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.35))
                    )
            }
            .padding(20)
        }
    }

    private var normalizedCodiceFiscale: String? {
        guard let codiceFiscale else { return nil }
        let trimmed = codiceFiscale.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }
}
