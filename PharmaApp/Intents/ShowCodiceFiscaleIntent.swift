import Foundation
import AppIntents

struct ShowCodiceFiscaleIntent: AppIntent {
    static var title: LocalizedStringResource = "Codice fiscale non disponibile"
    static var description = IntentDescription("La visualizzazione del codice fiscale non è più disponibile nell'app.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: SiriIntentSupport.dialog("Il codice fiscale non è più gestito in questa versione dell'app."))
    }
}
