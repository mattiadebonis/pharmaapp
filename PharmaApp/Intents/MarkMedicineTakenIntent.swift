import Foundation
import AppIntents

struct MarkMedicineTakenIntent: AppIntent {
    static var title: LocalizedStringResource = "Segna assunto"
    static var description = IntentDescription("Registra subito l'assunzione di un medicinale.")
    static var openAppWhenRun = false

    @Parameter(title: "Medicinale")
    var medicine: MedicineIntentEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = SiriIntentFacade.shared.markTaken(medicineID: medicine.id)
        let dialogText: String
        if result.succeeded {
            dialogText = "Segnato come assunto: \(result.medicineName ?? medicine.name)."
        } else {
            dialogText = result.message
        }
        return .result(dialog: SiriIntentSupport.dialog(dialogText))
    }
}
