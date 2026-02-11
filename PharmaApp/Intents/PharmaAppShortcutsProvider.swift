import AppIntents

struct PharmaAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkMedicineTakenIntent(),
            phrases: [
                "Segna assunto in \(.applicationName)",
                "Ho preso \(\.$medicine) in \(.applicationName)",
                "Segna assunto \(\.$medicine) in \(.applicationName)",
                "Registra assunzione \(\.$medicine) in \(.applicationName)"
            ],
            shortTitle: "Segna assunto",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: MarkMedicinePurchasedIntent(),
            phrases: [
                "Segna comprato \(\.$medicine) in \(.applicationName)",
                "Ho comprato \(\.$medicine) in \(.applicationName)",
                "Registra acquisto \(\.$medicine) in \(.applicationName)",
                "Segna acquisto \(\.$medicine) in \(.applicationName)"
            ],
            shortTitle: "Segna comprato",
            systemImageName: "cart"
        )
        AppShortcut(
            intent: MarkPrescriptionReceivedIntent(),
            phrases: [
                "Ho ricevuto la ricetta per \(\.$medicine) in \(.applicationName)",
                "Ricetta ricevuta \(\.$medicine) in \(.applicationName)",
                "Segna ricetta ricevuta per \(\.$medicine) in \(.applicationName)",
                "Registra ricetta \(\.$medicine) in \(.applicationName)"
            ],
            shortTitle: "Ricetta ricevuta",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: WhatShouldITakeNowIntent(),
            phrases: [
                "Cosa devo prendere in \(.applicationName)",
                "Cosa devo prendere adesso in \(.applicationName)",
                "Qual e la prossima assunzione in \(.applicationName)",
                "Prossima dose in \(.applicationName)"
            ],
            shortTitle: "Cosa prendere",
            systemImageName: "pills"
        )
        AppShortcut(
            intent: DidITakeEverythingTodayIntent(),
            phrases: [
                "Ho preso tutto per oggi in \(.applicationName)",
                "Ho preso tutto oggi in \(.applicationName)",
                "Verifica assunzioni di oggi in \(.applicationName)",
                "Controlla terapie di oggi in \(.applicationName)"
            ],
            shortTitle: "Tutto preso?",
            systemImageName: "checkmark.seal"
        )
        AppShortcut(
            intent: WhatShouldIBuyIntent(),
            phrases: [
                "Cosa devo comprare in \(.applicationName)",
                "Cosa manca da comprare in \(.applicationName)",
                "Lista acquisti in \(.applicationName)",
                "Mostra cosa comprare in \(.applicationName)"
            ],
            shortTitle: "Cosa comprare",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: ShowCodiceFiscaleIntent(),
            phrases: [
                "Mostra codice fiscale in \(.applicationName)",
                "Apri codice fiscale in \(.applicationName)",
                "Mostra tessera sanitaria in \(.applicationName)",
                "Apri barcode codice fiscale in \(.applicationName)"
            ],
            shortTitle: "Codice fiscale",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: NavigateToPharmacyIntent(),
            phrases: [
                "Portami in farmacia con \(.applicationName)",
                "Apri farmacia in \(.applicationName)",
                "Mostra farmacia suggerita in \(.applicationName)",
                "Vai in farmacia con \(.applicationName)"
            ],
            shortTitle: "Portami in farmacia",
            systemImageName: "mappin.and.ellipse"
        )
    }
}
