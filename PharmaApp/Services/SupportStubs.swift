import SwiftUI
import UIKit

// Placeholder per la conferma richiesta ricetta.
struct PrescriptionRequestConfirmationSheet: View {
    let medicineName: String
    let doctor: DoctorContact
    let subject: String
    let messageBody: String
    let onDidSend: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showMailFallbackAlert = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Richiesta ricetta")
                .font(.title2.weight(.semibold))
            Text("Invia richiesta a \(doctor.name) per \(medicineName)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    sendWhatsApp()
                } label: {
                    Label("WhatsApp + segna richiesta", systemImage: "message.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(doctor.phoneInternational == nil)

                Button {
                    sendMail()
                } label: {
                    Label("Email + segna richiesta", systemImage: "envelope.fill")
                }
                .buttonStyle(.bordered)
                .disabled(doctor.email == nil)
            }
        }
        .padding()
        .alert("Impossibile aprire Mail", isPresented: $showMailFallbackAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Testo copiato negli appunti. Installa o configura un'app Mail per inviare la richiesta.")
        }
    }

    private var communicationService: CommunicationService {
        CommunicationService(openURL: openURL)
    }

    private func sendWhatsApp() {
        guard doctor.phoneInternational != nil else { return }
        communicationService.sendWhatsApp(to: doctor, text: messageBody)
        onDidSend()
        dismiss()
    }

    private func sendMail() {
        guard doctor.email != nil else { return }
        communicationService.sendEmail(
            to: doctor,
            subject: subject,
            body: messageBody,
            onFailure: {
                UIPasteboard.general.string = messageBody
                showMailFallbackAlert = true
            }
        )
        onDidSend()
        dismiss()
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

