import Foundation
import UserNotifications

protocol CriticalDoseReminderScheduling {
    func scheduleReminder(
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        remindAt: Date,
        now: Date
    ) async
}

final class CriticalDoseReminderScheduler: CriticalDoseReminderScheduling {
    private let center: NotificationCenterClient

    init(center: NotificationCenterClient = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func scheduleReminder(
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        remindAt: Date,
        now: Date = Date()
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "È quasi ora"
        content.body = "\(contentState.primaryMedicineName) · \(contentState.primaryDoseText). Quando sei pronto."
        content.sound = .default
        content.threadIdentifier = NotificationPlanKind.therapy.rawValue
        content.categoryIdentifier = TherapyAlarmNotificationConstants.categoryIdentifier
        content.userInfo = [
            "type": NotificationPlanKind.therapy.rawValue,
            "therapyId": contentState.primaryTherapyId,
            "medicineId": contentState.primaryMedicineId
        ]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger: UNNotificationTrigger
        if remindAt.timeIntervalSince(now) <= 1 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        } else {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: remindAt
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let bucket = Int(contentState.primaryScheduledAt.timeIntervalSince1970 / 60)
        let requestID = "critical-dose-reminder-\(contentState.primaryTherapyId)-\(bucket)"
        center.removePendingNotificationRequests(withIdentifiers: [requestID])

        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // Skip on scheduling errors to keep actions non-blocking.
        }
    }
}
