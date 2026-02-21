import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

struct RefillActivityAttributes {
    struct ContentState: Codable, Hashable {
        let primaryText: String
        let pharmacyName: String?
        let etaMinutes: Int?
        let distanceMeters: Double?
        let pharmacyHoursText: String?
        let purchaseNames: [String]
        let remainingPurchaseCount: Int
        let doctorName: String
        let doctorHoursText: String
        let lastUpdatedAt: Date
        let showHealthCardAction: Bool
    }

    let pharmacyId: String
    let pharmacyName: String
    let latitude: Double
    let longitude: Double
}

#if canImport(ActivityKit)
extension RefillActivityAttributes: ActivityAttributes {}
#endif
