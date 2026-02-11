import Foundation
import AppIntents

struct DidITakeEverythingTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Ho preso tutto oggi"
    static var description = IntentDescription("Controlla le dosi pianificate oggi confrontandole con i log di assunzione.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let status = SiriIntentFacade.shared.doneTodayStatus()

        if status.totalPlanned == 0 {
            return .result(dialog: SiriIntentSupport.dialog("Oggi non risultano assunzioni pianificate."))
        }

        if status.isDone {
            let text = "Si, risulta tutto preso per oggi (\(status.totalTaken)/\(status.totalPlanned))."
            return .result(dialog: SiriIntentSupport.dialog(text))
        }

        let missing = SiriIntentSupport.joinedList(Array(status.missingMedicines.prefix(3)))
        let suffix = status.missingMedicines.count > 3 ? " e altri \(status.missingMedicines.count - 3)." : "."
        let text = "Non ancora. Mancano: \(missing)\(suffix)"
        return .result(dialog: SiriIntentSupport.dialog(text))
    }
}
