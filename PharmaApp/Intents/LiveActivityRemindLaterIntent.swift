import Foundation
import AppIntents

struct LiveActivityRemindLaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Ricordamelo dopo"
    static var description = IntentDescription("Rimanda di 10 minuti la dose principale della Live Activity È quasi ora.")
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

        let success = await Self.actionPerformer.remindLater(contentState: content, now: Date())
        _ = await Self.liveActivityRefresher.refresh(reason: "intent-remind-later", now: nil)

        let dialog = success
            ? "Va bene, te lo ricordo tra 10 minuti."
            : "Non sono riuscito a rimandare il promemoria in questo momento."
        return .result(dialog: SiriIntentSupport.dialog(dialog))
    }
}
