import Foundation
import AppIntents

struct WhatShouldITakeNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Cosa devo prendere"
    static var description = IntentDescription("Legge il prossimo evento di assunzione e suggerisce il comando rapido per registrarlo.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = SiriIntentFacade.shared.nextDoseNow() else {
            return .result(dialog: SiriIntentSupport.dialog("Non ci sono assunzioni pianificate in questo momento."))
        }

        let timeText = SiriIntentSupport.timeFormatter.string(from: next.scheduledAt)
        var message = "Prossima assunzione alle \(timeText): \(next.medicine.name)"
        if let dose = next.doseSummary, !dose.isEmpty {
            message += ", dose \(dose)"
        }
        message += ". Se vuoi registrarla subito, di 'Ho preso \(next.medicine.name)'."

        return .result(dialog: SiriIntentSupport.dialog(message))
    }
}
