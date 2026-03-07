import Foundation

@MainActor
enum IntentsGatewayBridge {
    static var gateway: any IntentsGateway {
        if let provider = AppDataProviderRegistry.shared.provider {
            return provider.intents
        }
        return legacyGateway
    }

    private static let legacyGateway: any IntentsGateway = LegacySiriIntentsGateway()
}

@MainActor
private final class LegacySiriIntentsGateway: IntentsGateway {
    private let facade = SiriIntentFacade.shared

    func queueRoute(_ route: AppRoute) {
        facade.queueRoute(route)
    }

    func suggestedMedicines(limit: Int) -> [MedicineIntentEntity] {
        facade.suggestedMedicines(limit: limit)
    }

    func medicines(matching query: String, limit: Int) -> [MedicineIntentEntity] {
        facade.medicines(matching: query, limit: limit)
    }

    func medicines(withIDs ids: [String]) -> [MedicineIntentEntity] {
        facade.medicines(withIDs: ids)
    }

    func markTaken(medicineID: String) -> SiriActionExecution {
        facade.markTaken(medicineID: medicineID)
    }

    func markPurchased(medicineID: String) -> SiriActionExecution {
        facade.markPurchased(medicineID: medicineID)
    }

    func markPrescriptionReceived(medicineID: String) -> SiriActionExecution {
        facade.markPrescriptionReceived(medicineID: medicineID)
    }

    func nextDoseNow(now: Date) -> SiriNextDoseNow? {
        facade.nextDoseNow(now: now)
    }

    func doneTodayStatus(now: Date) -> SiriDoneTodayStatus {
        facade.doneTodayStatus(now: now)
    }

    func purchaseSummary(maxItems: Int) -> SiriPurchaseSummary {
        facade.purchaseSummary(maxItems: maxItems)
    }
}
