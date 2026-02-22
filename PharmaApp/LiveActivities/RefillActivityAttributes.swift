import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

struct RefillActivityAttributes {
    struct CFDisplayEntry: Codable, Hashable {
        let personName: String
        let codiceFiscale: String
    }

    struct PurchaseItem: Codable, Hashable {
        let name: String
        let autonomyDays: Int?
        let remainingUnits: Int?
    }

    struct ContentState: Codable, Hashable {
        let primaryText: String
        let pharmacyName: String?
        let etaMinutes: Int?
        let distanceMeters: Double?
        let pharmacyHoursText: String?
        let purchaseNames: [String]
        let purchaseItems: [PurchaseItem]
        let isWalking: Bool
        let isPharmacyOpen: Bool
        let codiceFiscaleEntries: [CFDisplayEntry]
        let lastUpdatedAt: Date

        init(
            primaryText: String,
            pharmacyName: String?,
            etaMinutes: Int?,
            distanceMeters: Double?,
            pharmacyHoursText: String?,
            purchaseNames: [String],
            purchaseItems: [PurchaseItem] = [],
            isWalking: Bool = true,
            isPharmacyOpen: Bool = false,
            codiceFiscaleEntries: [CFDisplayEntry],
            lastUpdatedAt: Date
        ) {
            self.primaryText = primaryText
            self.pharmacyName = pharmacyName
            self.etaMinutes = etaMinutes
            self.distanceMeters = distanceMeters
            self.pharmacyHoursText = pharmacyHoursText
            self.purchaseNames = purchaseNames
            self.purchaseItems = purchaseItems
            self.isWalking = isWalking
            self.isPharmacyOpen = isPharmacyOpen
            self.codiceFiscaleEntries = codiceFiscaleEntries
            self.lastUpdatedAt = lastUpdatedAt
        }
    }

    let pharmacyId: String
    let pharmacyName: String
    let latitude: Double
    let longitude: Double
}

#if canImport(ActivityKit)
extension RefillActivityAttributes: ActivityAttributes {}
#endif
