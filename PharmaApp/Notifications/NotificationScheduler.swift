import Foundation
import CoreData
import UserNotifications
import os.signpost

enum NotificationInterruptionPriority: Equatable {
    case active
    case timeSensitive
}

struct NotificationScheduleRequestDescriptor: Equatable {
    let identifier: String
    let date: Date
    let title: String
    let body: String
    let userInfo: [String: String]
    let threadIdentifier: String
    let categoryIdentifier: String
    let interruptionLevel: NotificationInterruptionPriority
}

final class NotificationScheduler {
    private let center: NotificationCenterClient
    private let context: NSManagedObjectContext
    private let config: NotificationScheduleConfiguration
    private let planner: NotificationPlanner
    private let perfLog = OSLog(subsystem: "PharmaApp", category: "Performance")
    private var isScheduling = false
    private var needsReschedule = false

    init(
        center: NotificationCenterClient = UNUserNotificationCenter.current(),
        context: NSManagedObjectContext,
        config: NotificationScheduleConfiguration = NotificationScheduleConfiguration(),
        stockAlertStore: StockAlertStateStore = UserDefaultsStockAlertStateStore()
    ) {
        self.center = center
        self.context = context
        self.config = config
        self.planner = NotificationPlanner(
            context: context,
            calendar: .current,
            config: config,
            stockAlertStore: stockAlertStore
        )
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                var options: UNAuthorizationOptions = [.alert, .sound, .badge]
                if #available(iOS 15.0, *) {
                    options.insert(.timeSensitive)
                }
                return try await center.requestAuthorization(options: options)
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func rescheduleAll(reason: String? = nil) async {
        guard !isScheduling else {
            needsReschedule = true
            return
        }
        let signpostID = OSSignpostID(log: perfLog)
        os_signpost(.begin, log: perfLog, name: "NotificationPlan", signpostID: signpostID)
        defer { os_signpost(.end, log: perfLog, name: "NotificationPlan", signpostID: signpostID) }

        isScheduling = true
        defer {
            isScheduling = false
            if needsReschedule {
                needsReschedule = false
                Task { [weak self] in
                    await self?.rescheduleAll(reason: "queued")
                }
            }
        }

        let authorized = await requestAuthorizationIfNeeded()
        guard authorized else { return }

        let now = Date()
        let (plan, preferences) = makePlanAndPreferences(now: now)
        let therapyItems = Array(plan.therapy.prefix(config.maxTherapyNotifications))
        let stockItems = Array(plan.stock.prefix(config.maxStockNotifications))

        let combined = (therapyItems + stockItems).sorted { $0.date < $1.date }
        let items = Array(combined.prefix(config.maxTotalNotifications))
        let descriptors = Self.buildRequestDescriptors(
            items: items,
            preferences: preferences,
            now: now,
            pendingCap: config.maxTotalNotifications
        )

        await removePendingNotifications(withPrefixes: ["therapy-", "stock-"])
        await schedule(descriptors: descriptors, now: now)
        await ensureTherapyBackupIfNeeded(
            therapyItems: therapyItems,
            preferences: preferences,
            now: now
        )
    }

    private func makePlanAndPreferences(now: Date) -> (NotificationPlan, TherapyNotificationPreferences) {
        context.performAndWait {
            let preferences = TherapyNotificationPreferences(option: Option.current(in: context))
            let plan = planner.plan(now: now)
            return (plan, preferences)
        }
    }

    nonisolated static func buildRequestDescriptors(
        items: [NotificationPlanItem],
        preferences: TherapyNotificationPreferences,
        now: Date,
        pendingCap: Int
    ) -> [NotificationScheduleRequestDescriptor] {
        var descriptors: [NotificationScheduleRequestDescriptor] = []
        for item in items {
            let baseDate = item.origin == .immediate ? now.addingTimeInterval(1) : item.date
            if item.kind == .therapy, preferences.level == .alarm {
                let seriesId = UUID().uuidString
                for index in 0...TherapyNotificationPreferences.alarmRepeatCount {
                    var userInfo = item.userInfo
                    userInfo[TherapyAlarmNotificationConstants.alarmSeriesIdKey] = seriesId
                    descriptors.append(
                        NotificationScheduleRequestDescriptor(
                            identifier: TherapyNotificationPreferences.alarmIdentifier(
                                seriesId: seriesId,
                                index: index
                            ),
                            date: TherapyNotificationPreferences.alarmDate(
                                baseDate: baseDate,
                                index: index
                            ),
                            title: item.title,
                            body: item.body,
                            userInfo: userInfo,
                            threadIdentifier: item.kind.rawValue,
                            categoryIdentifier: TherapyAlarmNotificationConstants.categoryIdentifier,
                            interruptionLevel: .timeSensitive
                        )
                    )
                }
                continue
            }

            let interruptionLevel: NotificationInterruptionPriority = item.kind == .therapy
                ? .timeSensitive
                : .active
            descriptors.append(
                NotificationScheduleRequestDescriptor(
                    identifier: item.id,
                    date: baseDate,
                    title: item.title,
                    body: item.body,
                    userInfo: item.userInfo,
                    threadIdentifier: item.kind.rawValue,
                    categoryIdentifier: item.kind.rawValue,
                    interruptionLevel: interruptionLevel
                )
            )
        }

        return Array(
            descriptors
                .sorted { lhs, rhs in
                    if lhs.date == rhs.date {
                        return lhs.identifier < rhs.identifier
                    }
                    return lhs.date < rhs.date
                }
                .prefix(max(0, pendingCap))
        )
    }

    private func removePendingNotifications(withPrefixes prefixes: [String]) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map { $0.identifier }
            .filter { id in
                prefixes.contains { id.hasPrefix($0) }
            }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func schedule(descriptors: [NotificationScheduleRequestDescriptor], now: Date) async {
        for descriptor in descriptors {
            let content = UNMutableNotificationContent()
            content.title = descriptor.title
            content.body = descriptor.body
            content.sound = .default
            content.userInfo = descriptor.userInfo
            content.threadIdentifier = descriptor.threadIdentifier
            content.categoryIdentifier = descriptor.categoryIdentifier
            if #available(iOS 15.0, *) {
                switch descriptor.interruptionLevel {
                case .active:
                    content.interruptionLevel = .active
                case .timeSensitive:
                    content.interruptionLevel = .timeSensitive
                }
            }

            let trigger = makeTrigger(for: descriptor.date, now: now)
            let request = UNNotificationRequest(
                identifier: descriptor.identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                // Skip failed schedules but continue scheduling the rest.
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

    private func ensureTherapyBackupIfNeeded(
        therapyItems: [NotificationPlanItem],
        preferences: TherapyNotificationPreferences,
        now: Date
    ) async {
        guard !therapyItems.isEmpty else { return }
        let pending = await center.pendingNotificationRequests()
        let hasTherapyPending = pending.contains { $0.identifier.hasPrefix("therapy-") }
        guard !hasTherapyPending else { return }

        let nextItem = therapyItems
            .sorted { $0.date < $1.date }
            .first { $0.date > now } ?? therapyItems.first
        guard let fallback = nextItem else { return }

        let fallbackCap = preferences.level == .alarm
            ? TherapyNotificationPreferences.alarmRepeatCount + 1
            : 1
        let fallbackDescriptors = Self.buildRequestDescriptors(
            items: [fallback],
            preferences: preferences,
            now: now,
            pendingCap: fallbackCap
        )
        await schedule(descriptors: fallbackDescriptors, now: now)
    }
}
