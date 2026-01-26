import Foundation
import CoreData
import UserNotifications

@MainActor
final class NotificationScheduler {
    private let center: NotificationCenterClient
    private let context: NSManagedObjectContext
    private let config: NotificationScheduleConfiguration
    private let planner: NotificationPlanner
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

        let plan = planner.plan(now: Date())
        let therapyItems = Array(plan.therapy.prefix(config.maxTherapyNotifications))
        let stockItems = Array(plan.stock.prefix(config.maxStockNotifications))

        let combined = (therapyItems + stockItems).sorted { $0.date < $1.date }
        let items = Array(combined.prefix(config.maxTotalNotifications))

        await removePendingNotifications(withPrefixes: ["therapy-", "stock-"])
        await schedule(items: items)
        await ensureTherapyBackupIfNeeded(therapyItems: therapyItems)
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

    private func schedule(items: [NotificationPlanItem]) async {
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = item.userInfo
            content.threadIdentifier = item.kind.rawValue
            content.categoryIdentifier = item.kind.rawValue
            if #available(iOS 15.0, *) {
                content.interruptionLevel = item.kind == .therapy ? .timeSensitive : .active
            }

            let trigger: UNNotificationTrigger
            if item.origin == .immediate {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            } else {
                let components = Calendar.current.dateComponents([
                    .year, .month, .day, .hour, .minute, .second
                ], from: item.date)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }

            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                // Skip failed schedules but continue scheduling the rest.
                continue
            }
        }
    }

    private func ensureTherapyBackupIfNeeded(therapyItems: [NotificationPlanItem]) async {
        guard !therapyItems.isEmpty else { return }
        let pending = await center.pendingNotificationRequests()
        let hasTherapyPending = pending.contains { $0.identifier.hasPrefix("therapy-") }
        guard !hasTherapyPending else { return }

        let now = Date()
        let nextItem = therapyItems
            .sorted { $0.date < $1.date }
            .first { $0.date > now } ?? therapyItems.first
        guard let fallback = nextItem else { return }

        let interval = max(5, fallback.date.timeIntervalSince(now))
        let content = UNMutableNotificationContent()
        content.title = fallback.title
        content.body = fallback.body
        content.sound = .default
        content.userInfo = fallback.userInfo
        content.threadIdentifier = fallback.kind.rawValue
        content.categoryIdentifier = fallback.kind.rawValue
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "therapy-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            // Ignore backup failure; primary scheduling already attempted.
        }
    }
}
