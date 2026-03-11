import AppIntents

struct PharmaAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
