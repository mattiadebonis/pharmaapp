import Foundation
import AppIntents

struct LiveActivityMarkTakenIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrazione automatica"
    static var description = IntentDescription("La registrazione manuale non è disponibile: la dose viene registrata automaticamente.")
    static var openAppWhenRun = false

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

    func perform() async throws -> some IntentResult {
        // The intent is executed in the main app process, not here.
        return .result()
    }
}
