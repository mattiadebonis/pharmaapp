import Foundation
import AppIntents

struct LiveActivityMarkTakenIntent: AppIntent {
    static var title: LocalizedStringResource = "Assunto"
    static var description = IntentDescription("Segna come assunta la dose principale della Live Activity È quasi ora.")
    static var openAppWhenRun = false
    @MainActor static var actionPerformer: CriticalDoseActionPerforming = CriticalDoseActionService.shared
    @MainActor static var liveActivityRefresher: CriticalDoseLiveActivityRefreshing = CriticalDoseLiveActivityCoordinator.shared

    @Parameter(title: "Terapia")
    var therapyId: String

    @Parameter(title: "Medicinale")
    var medicineId: String

    @Parameter(title: "Nome")
    var medicineName: String

    @Parameter(title: "Dose")
    var doseText: String

    @Parameter(title: "Orario")
    var scheduledAt: Date

    init() {}

    init(
        therapyId: String,
        medicineId: String,
        medicineName: String,
        doseText: String,
        scheduledAt: Date
    ) {
        self.therapyId = therapyId
        self.medicineId = medicineId
        self.medicineName = medicineName
        self.doseText = doseText
        self.scheduledAt = scheduledAt
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content = CriticalDoseLiveActivityAttributes.ContentState(
            primaryTherapyId: therapyId,
            primaryMedicineId: medicineId,
            primaryMedicineName: medicineName,
            primaryDoseText: doseText,
            primaryScheduledAt: scheduledAt,
            additionalCount: 0,
            subtitleDisplay: "\(medicineName) · \(doseText)",
            expiryAt: scheduledAt
        )

        let success = await Self.actionPerformer.markTaken(contentState: content)

        if success {
            await Self.liveActivityRefresher.showConfirmationThenRefresh(medicineName: medicineName)
        } else {
            _ = await Self.liveActivityRefresher.refresh(reason: "intent-assunto", now: nil)
        }

        let dialog = success
            ? "Perfetto, segnato come assunto."
            : "Non sono riuscito a segnare l'assunzione in questo momento."
        return .result(dialog: SiriIntentSupport.dialog(dialog))
    }
}
