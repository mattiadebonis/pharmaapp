import Foundation
import AppIntents

struct MarkMedicinePurchasedIntent: AppIntent {
    static var title: LocalizedStringResource = "Segna comprato"
    static var description = IntentDescription("Registra un acquisto o aggiornamento scorte per un medicinale.")
    static var openAppWhenRun = false

    @Parameter(title: "Medicinale")
    var medicine: MedicineIntentEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = SiriIntentFacade.shared.markPurchased(medicineID: medicine.id)
        let dialogText: String
        if result.succeeded {
            dialogText = "Acquisto registrato per \(result.medicineName ?? medicine.name)."
        } else {
            dialogText = result.message
        }
        return .result(dialog: SiriIntentSupport.dialog(dialogText))
    }
}
