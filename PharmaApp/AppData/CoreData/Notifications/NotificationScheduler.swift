import Foundation
import CoreData
import CryptoKit
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
    let playsSound: Bool
}

final class NotificationScheduler {
    private let center: NotificationCenterClient
    private let alarmScheduler: AlarmScheduling
    private let context: NSManagedObjectContext
    private let config: NotificationScheduleConfiguration
    private let planner: NotificationPlanner
    private let perfLog = OSLog(subsystem: "PharmaApp", category: "Performance")
    private var isScheduling = false
    private var needsReschedule = false

    init(
        center: NotificationCenterClient = UNUserNotificationCenter.current(),
        alarmScheduler: AlarmScheduling = AlarmKitScheduler(),
        context: NSManagedObjectContext,
        config: NotificationScheduleConfiguration = NotificationScheduleConfiguration(),
        stockAlertStore: StockAlertStateStore = UserDefaultsStockAlertStateStore()
    ) {
        self.center = center
        self.alarmScheduler = alarmScheduler
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

        let now = Date()
        let (plan, preferences) = makePlanAndPreferences(now: now)
        let therapyItems = Array(plan.therapy.prefix(config.maxTherapyNotifications))
        let stockItems = Array(plan.stock.prefix(config.maxStockNotifications))

        let combined = (therapyItems + stockItems).sorted { $0.date < $1.date }
        let items = Array(combined.prefix(config.maxTotalNotifications))
        let alarmCandidates = items.filter(Self.shouldUseAlarmKit(for:))
        let notificationCandidates = items.filter { !Self.shouldUseAlarmKit(for: $0) }
        let alarmDescriptors = Self.buildAlarmDescriptors(items: alarmCandidates, now: now)
        let alarmOutcome = await alarmScheduler.schedule(descriptors: alarmDescriptors, now: now)
        let fallbackAlarmItemIDs = alarmOutcome.fallbackItemIds
        let fallbackAlarmItems = alarmCandidates.filter { fallbackAlarmItemIDs.contains($0.id) }
        let notificationItems = notificationCandidates + fallbackAlarmItems
        let descriptors = Self.buildRequestDescriptors(
            items: notificationItems,
            preferences: preferences,
            now: now,
            pendingCap: config.maxTotalNotifications
        )

        await removePendingNotifications(withPrefixes: ["therapy-", "stock-"])
        guard !descriptors.isEmpty else { return }
        let authorized = await requestAuthorizationIfNeeded()
        guard authorized else { return }
        await schedule(descriptors: descriptors, now: now)
        await ensureTherapyBackupIfNeeded(
            therapyItems: notificationItems.filter { $0.kind == .therapy },
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
            if item.kind == .therapy, item.notificationLevel == .alarm, !item.isSilenced {
                let seriesId = UUID().uuidString
                for index in 0...TherapyNotificationPreferences.alarmRepeatCount {
                    var userInfo = item.userInfo
                    userInfo[TherapyAlarmNotificationConstants.alarmSeriesIdKey] = seriesId
                    userInfo["snoozeMinutes"] = String(item.snoozeMinutes)
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
                            interruptionLevel: .timeSensitive,
                            playsSound: true
                        )
                    )
                }
                continue
            }

            let interruptionLevel: NotificationInterruptionPriority = item.kind == .therapy && !item.isSilenced
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
                    interruptionLevel: interruptionLevel,
                    playsSound: !item.isSilenced
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

    nonisolated static func buildAlarmDescriptors(
        items: [NotificationPlanItem],
        now: Date
    ) -> [AlarmScheduleDescriptor] {
        items.map { item in
            let baseDate = item.origin == .immediate ? now.addingTimeInterval(1) : item.date
            let seed = [
                "alarmkit",
                item.kind.rawValue,
                item.userInfo["therapyId"] ?? "",
                item.userInfo["medicineId"] ?? "",
                item.userInfo[NotificationPlanUserInfoKey.nextDoseAt] ?? "",
                String(Int(baseDate.timeIntervalSince1970 / 60))
            ].joined(separator: "|")
            return AlarmScheduleDescriptor(
                id: deterministicUUID(seed: seed),
                sourceItemId: item.id,
                date: baseDate,
                title: item.title,
                body: item.body,
                kind: item.kind,
                snoozeMinutes: item.kind == .therapy ? item.snoozeMinutes : nil
            )
        }
    }

    nonisolated static func shouldUseAlarmKit(for item: NotificationPlanItem) -> Bool {
        if item.kind == .therapy {
            return item.notificationLevel == .alarm && !item.isSilenced
        }
        return item.userInfo[NotificationPlanUserInfoKey.nextDoseInsufficient] == "1"
    }

    nonisolated static func deterministicUUID(seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
            content.sound = descriptor.playsSound ? .default : nil
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

        let fallbackCap = fallback.notificationLevel == .alarm
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
