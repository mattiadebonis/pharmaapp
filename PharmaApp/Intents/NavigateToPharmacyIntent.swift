import Foundation
import AppIntents

struct NavigateToPharmacyIntent: AppIntent {
    static var title: LocalizedStringResource = "Portami in farmacia"
    static var description = IntentDescription("Apre la schermata farmacia suggerita con azioni di navigazione Apple Maps.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            IntentsGatewayBridge.gateway.queueRoute(.pharmacy)
        }
        return .result(dialog: SiriIntentSupport.dialog("Ti porto alla schermata farmacia suggerita."))
    }
}
