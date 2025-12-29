import SwiftUI
import MapKit

// Placeholder per la conferma richiesta ricetta.
struct PrescriptionRequestConfirmationSheet: View {
    let medicineName: String
    let doctor: DoctorContact
    let subject: String
    let messageBody: String
    let onDidSend: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Richiesta ricetta")
                .font(.title2.weight(.semibold))
            Text("Invia richiesta a \(doctor.name) per \(medicineName)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Invia") { onDidSend() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// Placeholder per l'email di richiesta ricetta.
struct PrescriptionEmailSheet: View {
    let doctor: DoctorContact
    let subject: String
    let messageBody: String
    let onCopy: () -> Void
    let onDidSend: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Email a \(doctor.name)")
                .font(.title2.weight(.semibold))
            Text(subject)
                .font(.headline)
            Text(messageBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            HStack {
                Button("Copia") { onCopy() }
                    .buttonStyle(.bordered)
                Button("Segna come inviata") { onDidSend() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// Contesto usato per generare insight e todo.
struct AIInsightsContext {
    let purchaseHighlights: [String]
    let therapyHighlights: [String]
    let upcomingHighlights: [String]
    let prescriptionHighlights: [String]
    let pharmacySuggestion: String?

    var hasSignals: Bool {
        !purchaseHighlights.isEmpty ||
        !therapyHighlights.isEmpty ||
        !upcomingHighlights.isEmpty ||
        !prescriptionHighlights.isEmpty ||
        pharmacySuggestion != nil
    }
}
