import Foundation
import AppIntents

struct DismissRefillActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Non ora"
    static var description = IntentDescription("Chiude la Live Activity Rifornimenti senza attivare blocchi aggiuntivi.")
    static var openAppWhenRun = false

    @MainActor static var dismissHandler: RefillLiveActivityDismissHandling = RefillLiveActivityCoordinator.shared

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await Self.dismissHandler.dismissCurrentActivity(reason: "intent-non-ora")
        return .result(dialog: SiriIntentSupport.dialog("Va bene, per ora non te lo mostro."))
    }
}
