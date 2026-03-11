import Foundation
import AppIntents

struct MarkMedicineTakenIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrazione automatica dose"
    static var description = IntentDescription("La registrazione manuale è disattivata: l'assunzione viene registrata automaticamente.")
    static var openAppWhenRun = false

    @Parameter(title: "Medicinale")
    var medicine: MedicineIntentEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialogText = "Le assunzioni vengono registrate automaticamente all'orario della terapia."
        return .result(dialog: SiriIntentSupport.dialog(dialogText))
    }
}
