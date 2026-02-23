import Foundation
import AppIntents

struct WhatShouldIBuyIntent: AppIntent {
    static var title: LocalizedStringResource = "Cosa devo comprare"
    static var description = IntentDescription("Riepiloga i medicinali da comprare e apre la lista completa nell'app.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = SiriIntentFacade.shared.purchaseSummary(maxItems: 3)
        SiriIntentFacade.shared.queueRoute(.pharmacy)

        guard summary.totalCount > 0 else {
            return .result(dialog: SiriIntentSupport.dialog("Al momento non risultano acquisti urgenti. Ti apro comunque la lista completa."))
        }

        let top = SiriIntentSupport.joinedList(summary.items)
        let suffix = summary.remainingCount > 0 ? " e altri \(summary.remainingCount)." : "."
        let text = "Da comprare: \(top)\(suffix) Ti apro la lista completa."
        return .result(dialog: SiriIntentSupport.dialog(text))
    }
}
