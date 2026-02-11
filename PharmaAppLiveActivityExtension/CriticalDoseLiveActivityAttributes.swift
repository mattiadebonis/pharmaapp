import Foundation
import ActivityKit

struct CriticalDoseLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let primaryTherapyId: String
        let primaryMedicineId: String
        let primaryMedicineName: String
        let primaryDoseText: String
        let primaryScheduledAt: Date
        let additionalCount: Int
        let subtitleDisplay: String
        let expiryAt: Date
    }

    let title: String
    let microcopy: String
}
