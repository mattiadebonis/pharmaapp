import Foundation
import AppIntents

struct MarkPrescriptionReceivedIntent: AppIntent {
    static var title: LocalizedStringResource = "Ricetta ricevuta"
    static var description = IntentDescription("Registra che hai ricevuto la ricetta per un medicinale.")
    static var openAppWhenRun = false

    @Parameter(title: "Medicinale")
    var medicine: MedicineIntentEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = SiriIntentFacade.shared.markPrescriptionReceived(medicineID: medicine.id)
        let dialogText: String
        if result.succeeded {
            dialogText = "Ho registrato la ricetta ricevuta per \(result.medicineName ?? medicine.name)."
        } else {
            dialogText = result.message
        }
        return .result(dialog: SiriIntentSupport.dialog(dialogText))
    }
}
