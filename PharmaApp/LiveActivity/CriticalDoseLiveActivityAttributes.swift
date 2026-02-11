import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

struct CriticalDoseLiveActivityAttributes {
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

#if canImport(ActivityKit)
extension CriticalDoseLiveActivityAttributes: ActivityAttributes {}
#endif
