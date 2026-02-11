import SwiftUI
import UIKit

// MARK: - Modelli

struct DoctorContact {
    let name: String
    let email: String?
    /// Numero in formato internazionale, solo cifre, senza "+" e senza zeri iniziali.
    /// Esempio: "393471234567"
    let phoneInternational: String?
}

// MARK: - Servizio

/// Servizio riutilizzabile per aprire app esterne (Mail/WhatsApp) via URL scheme.
///
/// Nota: non usa backend. L’invio avviene tramite l’app installata che gestisce lo schema.
@MainActor
final class CommunicationService {
    private let openURL: OpenURLAction

    init(openURL: OpenURLAction) {
        self.openURL = openURL
    }

    // MARK: Email

    func sendEmail(
        to doctor: DoctorContact,
        subject: String,
        body: String,
        onFailure: (() -> Void)? = nil
    ) {
        guard let email = doctor.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            print("CommunicationService.sendEmail: email mancante per \(doctor.name)")
            onFailure?()
            return
        }

        guard let url = Self.makeMailtoURL(email: email, subject: subject, body: body) else {
            print("CommunicationService.sendEmail: impossibile creare URL mailto")
            onFailure?()
            return
        }

        guard UIApplication.shared.canOpenURL(url) else {
            print("CommunicationService.sendEmail: nessuna app mail disponibile per \(doctor.name)")
            onFailure?()
            return
        }

        openURL(url) { success in
            if success { return }
            UIApplication.shared.open(url, options: [:]) { opened in
                if !opened {
                    print("CommunicationService.sendEmail: apertura Mail fallita per \(doctor.name)")
                    onFailure?()
                }
            }
        }
    }

    // MARK: WhatsApp

    func sendWhatsApp(to doctor: DoctorContact, text: String) {
        guard let rawPhone = doctor.phoneInternational,
              let phone = Self.normalizeInternationalPhone(rawPhone) else {
            print("CommunicationService.sendWhatsApp: numero mancante/non valido per \(doctor.name)")
            return
        }

        guard let appURL = Self.makeWhatsAppAppURL(phoneInternational: phone, text: text) else {
            print("CommunicationService.sendWhatsApp: impossibile creare URL whatsapp://")
            return
        }

        // Per usare canOpenURL con whatsapp:// ricordati di aggiungere in Info.plist (Target -> Info):
        // LSApplicationQueriesSchemes
        //   - whatsapp
        //
        // oppure in XML:
        /*
         <key>LSApplicationQueriesSchemes</key>
         <array>
             <string>whatsapp</string>
         </array>
         */
        if UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }

        guard let webURL = Self.makeWhatsAppWebURL(phoneInternational: phone, text: text) else {
            print("CommunicationService.sendWhatsApp: impossibile creare URL wa.me")
            return
        }

        openURL(webURL)
    }

    // MARK: - URL Builders

    static func makeMailtoURL(email: String, subject: String, body: String) -> URL? {
        guard let encodedSubject = encodeQueryValue(subject),
              let encodedBody = encodeQueryValue(body) else {
            return nil
        }

        let urlString = "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)"
        return URL(string: urlString)
    }

    static func makeWhatsAppAppURL(phoneInternational: String, text: String) -> URL? {
        guard let encodedText = encodeQueryValue(text) else { return nil }
        let urlString = "whatsapp://send?phone=\(phoneInternational)&text=\(encodedText)"
        return URL(string: urlString)
    }

    static func makeWhatsAppWebURL(phoneInternational: String, text: String) -> URL? {
        guard let encodedText = encodeQueryValue(text) else { return nil }
        let urlString = "https://wa.me/\(phoneInternational)?text=\(encodedText)"
        return URL(string: urlString)
    }

    // MARK: - Helpers

    /// Percent-encoding robusto per valori di query string.
    private static func encodeQueryValue(_ value: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    /// Normalizza un numero "internazionale" togliendo tutto ciò che non è cifra,
    /// rimuovendo eventuale prefisso "00" e zeri iniziali.
    static func normalizeInternationalPhone(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        var cleaned = digits
        if cleaned.hasPrefix("00") {
            cleaned.removeFirst(2)
        }
        while cleaned.hasPrefix("0") {
            cleaned.removeFirst()
        }
        return cleaned.isEmpty ? nil : cleaned
    }
}
