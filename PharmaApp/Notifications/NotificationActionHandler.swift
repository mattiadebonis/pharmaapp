import Foundation
import CoreData
import UserNotifications

@MainActor
final class NotificationActionHandler {
    private let center: NotificationCenterClient
    private let context: NSManagedObjectContext

    init(
        center: NotificationCenterClient = UNUserNotificationCenter.current(),
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) {
        self.center = center
        self.context = context
    }

    func handle(response: UNNotificationResponse, now: Date = Date()) async {
        await handleAction(
            actionIdentifier: response.actionIdentifier,
            requestIdentifier: response.notification.request.identifier,
            content: response.notification.request.content,
            now: now
        )
    }

    func handleAction(
        actionIdentifier: String,
        requestIdentifier: String,
        content: UNNotificationContent,
        now: Date = Date()
    ) async {
        guard content.categoryIdentifier == TherapyAlarmNotificationConstants.categoryIdentifier else { return }
        guard actionIdentifier == TherapyAlarmNotificationConstants.stopActionIdentifier
            || actionIdentifier == TherapyAlarmNotificationConstants.snoozeActionIdentifier else {
            return
        }
        guard let seriesId = resolveSeriesId(requestIdentifier: requestIdentifier, userInfo: content.userInfo) else {
            return
        }

        var seriesIds = Set(TherapyNotificationPreferences.alarmIdentifiers(seriesId: seriesId))
        seriesIds.insert(requestIdentifier)
        removeSeries(ids: Array(seriesIds))

        guard actionIdentifier == TherapyAlarmNotificationConstants.snoozeActionIdentifier else {
            return
        }
        let preferences = TherapyNotificationPreferences(option: Option.current(in: context))
        let nextSeriesId = UUID().uuidString
        let baseDate = now.addingTimeInterval(Double(preferences.snoozeMinutes * 60))
        await scheduleSnoozedSeries(
            from: content,
            seriesId: nextSeriesId,
            baseDate: baseDate,
            now: now
        )
    }

    private func removeSeries(ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func scheduleSnoozedSeries(
        from content: UNNotificationContent,
        seriesId: String,
        baseDate: Date,
        now: Date
    ) async {
        for index in 0...TherapyNotificationPreferences.alarmRepeatCount {
            let mutableContent = UNMutableNotificationContent()
            mutableContent.title = content.title
            mutableContent.subtitle = content.subtitle
            mutableContent.body = content.body
            mutableContent.badge = content.badge
            mutableContent.sound = .default
            mutableContent.launchImageName = content.launchImageName
            mutableContent.threadIdentifier = content.threadIdentifier
            mutableContent.categoryIdentifier = TherapyAlarmNotificationConstants.categoryIdentifier
            mutableContent.summaryArgument = content.summaryArgument
            mutableContent.summaryArgumentCount = content.summaryArgumentCount
            mutableContent.attachments = content.attachments
            if #available(iOS 15.0, *) {
                mutableContent.interruptionLevel = .timeSensitive
            }

            var userInfo = stringDictionary(from: content.userInfo)
            userInfo[TherapyAlarmNotificationConstants.alarmSeriesIdKey] = seriesId
            mutableContent.userInfo = userInfo

            let date = TherapyNotificationPreferences.alarmDate(baseDate: baseDate, index: index)
            let trigger = makeTrigger(for: date, now: now)
            let request = UNNotificationRequest(
                identifier: TherapyNotificationPreferences.alarmIdentifier(seriesId: seriesId, index: index),
                content: mutableContent,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                continue
            }
        }
    }

    private func makeTrigger(for date: Date, now: Date) -> UNNotificationTrigger {
        if date.timeIntervalSince(now) <= 1 {
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func resolveSeriesId(requestIdentifier: String, userInfo: [AnyHashable: Any]) -> String? {
        if let seriesId = userInfo[TherapyAlarmNotificationConstants.alarmSeriesIdKey] as? String,
           !seriesId.isEmpty {
            return seriesId
        }

        let prefix = "\(TherapyAlarmNotificationConstants.alarmIdentifierPrefix)-"
        guard requestIdentifier.hasPrefix(prefix) else { return nil }
        let remainder = String(requestIdentifier.dropFirst(prefix.count))
        guard let separatorIndex = remainder.lastIndex(of: "-"), separatorIndex > remainder.startIndex else {
            return nil
        }
        return String(remainder[..<separatorIndex])
    }

    private func stringDictionary(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var output: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            if let stringValue = value as? String {
                output[key] = stringValue
            }
        }
        return output
    }
}
