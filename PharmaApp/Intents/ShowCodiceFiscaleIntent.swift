import Foundation
import AppIntents

struct ShowCodiceFiscaleIntent: AppIntent {
    static var title: LocalizedStringResource = "Mostra codice fiscale"
    static var description = IntentDescription("Apre direttamente la visualizzazione fullscreen del codice fiscale.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriIntentFacade.shared.queueRoute(.codiceFiscaleFullscreen)
        return .result(dialog: SiriIntentSupport.dialog("Ti apro i codici fiscali associati alle ricette in corso."))
    }
}
