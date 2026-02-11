import Foundation
import AppIntents

struct OpenPurchaseListIntent: AppIntent {
    static var title: LocalizedStringResource = "Apri rifornimenti"
    static var description = IntentDescription("Apre la lista rifornimenti nella sezione Oggi.")
    static var openAppWhenRun = true

    @MainActor static var routeStore: PendingAppRouteStoring = PendingAppRouteStore()

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            Self.routeStore.save(route: .todayPurchaseList)
        }
        return .result(dialog: SiriIntentSupport.dialog("Ti apro la lista rifornimenti."))
    }
}
