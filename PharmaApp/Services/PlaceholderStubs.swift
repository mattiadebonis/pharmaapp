import SwiftUI
import MapKit

// Placeholder per la ricerca farmacia (sostituisce l'implementazione completa).
final class LocationSearchViewModel: ObservableObject {
    struct PinWrapper {
        let mapItem: MKMapItem
        var title: String { mapItem.name ?? "Farmacia" }
    }

    @Published var pinItem: PinWrapper?
    @Published var distanceString: String?
    @Published var distanceMeters: Double?
    @Published var closingTimeText: String?
    @Published var isLikelyOpen: Bool?
    @Published var todayOpeningText: String?

    func ensureStarted() { /* no-op placeholder */ }

    func openInMaps() {
        guard let item = pinItem?.mapItem else { return }
        item.openInMaps()
    }
}

// Placeholder per la finestra orari farmacia.
enum OpeningHoursParser {
    static func activeInterval(from: String, now: Date) -> String? { nil }
}

// Placeholder per il dettaglio di una mappa inline.
struct MapItemDetailInlineView: View {
    let mapItem: MKMapItem

    var body: some View {
        VStack(spacing: 8) {
            Text(mapItem.name ?? "Posizione")
                .font(.headline)
            if let address = mapItem.placemark.title {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

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

// Placeholder del contesto usato per generare insight e todo.
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
