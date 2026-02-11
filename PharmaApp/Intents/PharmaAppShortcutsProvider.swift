import AppIntents

struct PharmaAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkMedicineTakenIntent(),
            phrases: [
                "In \(.applicationName) segna assunto",
                "In \(.applicationName) ho preso \(\.$medicine)",
                "In \(.applicationName) segna assunto \(\.$medicine)",
                "In \(.applicationName) registra assunzione \(\.$medicine)"
            ],
            shortTitle: "Segna assunto",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: MarkMedicinePurchasedIntent(),
            phrases: [
                "In \(.applicationName) segna comprato \(\.$medicine)",
                "In \(.applicationName) ho comprato \(\.$medicine)",
                "In \(.applicationName) registra acquisto \(\.$medicine)",
                "In \(.applicationName) segna acquisto \(\.$medicine)"
            ],
            shortTitle: "Segna comprato",
            systemImageName: "cart"
        )
        AppShortcut(
            intent: MarkPrescriptionReceivedIntent(),
            phrases: [
                "In \(.applicationName) ho ricevuto la ricetta per \(\.$medicine)",
                "In \(.applicationName) ricetta ricevuta \(\.$medicine)",
                "In \(.applicationName) segna ricetta ricevuta per \(\.$medicine)",
                "In \(.applicationName) registra ricetta \(\.$medicine)"
            ],
            shortTitle: "Ricetta ricevuta",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: WhatShouldITakeNowIntent(),
            phrases: [
                "In \(.applicationName) cosa devo prendere",
                "In \(.applicationName) cosa devo prendere adesso",
                "In \(.applicationName) qual e la prossima assunzione",
                "In \(.applicationName) prossima dose"
            ],
            shortTitle: "Cosa prendere",
            systemImageName: "pills"
        )
        AppShortcut(
            intent: DidITakeEverythingTodayIntent(),
            phrases: [
                "In \(.applicationName) ho preso tutto per oggi",
                "In \(.applicationName) ho preso tutto oggi",
                "In \(.applicationName) verifica assunzioni di oggi",
                "In \(.applicationName) controlla terapie di oggi"
            ],
            shortTitle: "Tutto preso?",
            systemImageName: "checkmark.seal"
        )
        AppShortcut(
            intent: WhatShouldIBuyIntent(),
            phrases: [
                "In \(.applicationName) cosa devo comprare",
                "In \(.applicationName) cosa manca da comprare",
                "In \(.applicationName) lista acquisti",
                "In \(.applicationName) mostra cosa comprare"
            ],
            shortTitle: "Cosa comprare",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: OpenPurchaseListIntent(),
            phrases: [
                "In \(.applicationName) apri lista rifornimenti",
                "In \(.applicationName) apri da comprare",
                "In \(.applicationName) mostra rifornimenti",
                "In \(.applicationName) apri acquisti"
            ],
            shortTitle: "Apri rifornimenti",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: ShowCodiceFiscaleIntent(),
            phrases: [
                "In \(.applicationName) mostra codice fiscale",
                "In \(.applicationName) apri codice fiscale",
                "In \(.applicationName) mostra tessera sanitaria",
                "In \(.applicationName) apri barcode codice fiscale"
            ],
            shortTitle: "Codice fiscale",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: NavigateToPharmacyIntent(),
            phrases: [
                "In \(.applicationName) portami in farmacia",
                "In \(.applicationName) apri farmacia",
                "In \(.applicationName) mostra farmacia suggerita",
                "In \(.applicationName) vai in farmacia"
            ],
            shortTitle: "Portami in farmacia",
            systemImageName: "mappin.and.ellipse"
        )
    }
}
