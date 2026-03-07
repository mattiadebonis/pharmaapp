import Foundation
import AppIntents

struct OpenPurchaseListIntent: AppIntent {
    static var title: LocalizedStringResource = "Apri rifornimenti"
    static var description = IntentDescription("Apre la lista rifornimenti nell'app.")
    static var openAppWhenRun = true
    @MainActor static var routeStoreOverride: PendingAppRouteStoring?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            if let routeStore = Self.routeStoreOverride {
                routeStore.save(route: .pharmacy)
            } else {
                IntentsGatewayBridge.gateway.queueRoute(.pharmacy)
            }
        }
        return .result(dialog: SiriIntentSupport.dialog("Ti apro la lista rifornimenti."))
    }
}
