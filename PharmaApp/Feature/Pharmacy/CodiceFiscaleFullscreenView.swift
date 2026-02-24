import SwiftUI
import Code39

struct CodiceFiscaleFullscreenView: View {
    let entries: [PrescriptionCFEntry]
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.white
                .ignoresSafeArea()

            GeometryReader { _ in
                if entries.isEmpty {
                    VStack {
                        Spacer()
                        Text("Nessun CF disponibile per ricette o farmaci in esaurimento.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(entries) { entry in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(entry.personDisplayName)
                                        .font(.headline)
                                    Text(entry.medicineNames.joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Code39View(entry.codiceFiscale)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 120)
                                        .accessibilityLabel("Barcode Codice Fiscale")
                                        .accessibilityValue(entry.codiceFiscale)
                                    Text(entry.codiceFiscale)
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.systemGray6))
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 72)
                        .padding(.bottom, 24)
                    }
                }
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
}
