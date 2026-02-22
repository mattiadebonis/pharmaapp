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
        /// Non-nil when a dose has just been confirmed as taken; the widget shows a confirmation message.
        var confirmedTakenName: String?

        init(
            primaryTherapyId: String,
            primaryMedicineId: String,
            primaryMedicineName: String,
            primaryDoseText: String,
            primaryScheduledAt: Date,
            additionalCount: Int,
            subtitleDisplay: String,
            expiryAt: Date,
            confirmedTakenName: String? = nil
        ) {
            self.primaryTherapyId = primaryTherapyId
            self.primaryMedicineId = primaryMedicineId
            self.primaryMedicineName = primaryMedicineName
            self.primaryDoseText = primaryDoseText
            self.primaryScheduledAt = primaryScheduledAt
            self.additionalCount = additionalCount
            self.subtitleDisplay = subtitleDisplay
            self.expiryAt = expiryAt
            self.confirmedTakenName = confirmedTakenName
        }
    }

    let title: String
    let microcopy: String
}
