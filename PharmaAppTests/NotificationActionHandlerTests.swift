import Foundation
import UserNotifications
import Testing
@testable import PharmaApp

private final class ActionHandlerNotificationCenterClient: NotificationCenterClient {
    var addedRequests: [UNNotificationRequest] = []
    var removedPendingIds: [String] = []
    var removedDeliveredIds: [String] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }

    func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIds.append(contentsOf: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIds.append(contentsOf: identifiers)
    }
}

@MainActor
struct NotificationActionHandlerTests {
    @Test func stopRemovesWholeAlarmSeries() async throws {
        let center = ActionHandlerNotificationCenterClient()
        let handler = NotificationActionHandler(center: center)

        let seriesId = UUID().uuidString
        let requestIdentifier = TherapyNotificationPreferences.alarmIdentifier(seriesId: seriesId, index: 0)
        let content = makeAlarmContent(seriesId: seriesId)

        await handler.handleAction(
            actionIdentifier: TherapyAlarmNotificationConstants.stopActionIdentifier,
            requestIdentifier: requestIdentifier,
            content: content,
            now: Date(timeIntervalSince1970: 1_739_000_000)
        )

        let expected = Set(TherapyNotificationPreferences.alarmIdentifiers(seriesId: seriesId))
        #expect(Set(center.removedPendingIds) == expected)
        #expect(Set(center.removedDeliveredIds) == expected)
        #expect(center.addedRequests.isEmpty)
    }

    @Test func snoozeRemovesOldSeriesAndSchedulesNewSeries() async throws {
        let center = ActionHandlerNotificationCenterClient()
        let handler = NotificationActionHandler(center: center)

        let now = Date(timeIntervalSince1970: 1_739_000_000)
        let oldSeriesId = UUID().uuidString
        let requestIdentifier = TherapyNotificationPreferences.alarmIdentifier(seriesId: oldSeriesId, index: 2)
        let content = makeAlarmContent(seriesId: oldSeriesId)

        await handler.handleAction(
            actionIdentifier: TherapyAlarmNotificationConstants.snoozeActionIdentifier,
            requestIdentifier: requestIdentifier,
            content: content,
            now: now
        )

        let expectedRemoved = Set(TherapyNotificationPreferences.alarmIdentifiers(seriesId: oldSeriesId))
        #expect(Set(center.removedPendingIds) == expectedRemoved)
        #expect(Set(center.removedDeliveredIds) == expectedRemoved)

        #expect(center.addedRequests.count == 7)
        let newSeriesIds = Set(center.addedRequests.compactMap {
            $0.content.userInfo[TherapyAlarmNotificationConstants.alarmSeriesIdKey] as? String
        })
        #expect(newSeriesIds.count == 1)
        #expect(newSeriesIds.first != oldSeriesId)

        let scheduledDates = center.addedRequests.compactMap { request in
            (request.trigger as? UNCalendarNotificationTrigger).flatMap {
                Calendar.current.date(from: $0.dateComponents)
            }
        }.sorted()
        #expect(scheduledDates.count == 7)

        if let firstDate = scheduledDates.first {
            let delta = firstDate.timeIntervalSince(now)
            #expect(abs(delta - 900) < 2)
        }

        for index in 1..<scheduledDates.count {
            let delta = scheduledDates[index].timeIntervalSince(scheduledDates[index - 1])
            #expect(Int(delta) == 60)
        }
    }

    private func makeAlarmContent(seriesId: String) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "È ora della terapia"
        content.body = "Assumi terapia"
        content.sound = .default
        content.threadIdentifier = NotificationPlanKind.therapy.rawValue
        content.categoryIdentifier = TherapyAlarmNotificationConstants.categoryIdentifier
        content.userInfo = [
            "type": NotificationPlanKind.therapy.rawValue,
            "therapyId": "therapy-oid",
            "medicineId": UUID().uuidString,
            TherapyAlarmNotificationConstants.alarmSeriesIdKey: seriesId
        ]
        return content
    }
}
