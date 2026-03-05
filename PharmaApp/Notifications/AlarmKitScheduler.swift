import Foundation

#if canImport(AlarmKit) && canImport(SwiftUI) && !targetEnvironment(macCatalyst)
import AlarmKit
import SwiftUI
#endif

struct AlarmScheduleDescriptor: Equatable {
    let id: UUID
    let sourceItemId: String
    let date: Date
    let title: String
    let body: String
    let kind: NotificationPlanKind
    let snoozeMinutes: Int?
}

struct AlarmSchedulingOutcome: Equatable {
    let fallbackItemIds: Set<String>
}

protocol AlarmScheduling {
    func schedule(descriptors: [AlarmScheduleDescriptor], now: Date) async -> AlarmSchedulingOutcome
}

final class AlarmKitScheduler: AlarmScheduling {
    private let store: AlarmScheduledIDsStore

    init() {
        self.store = UserDefaultsAlarmScheduledIDsStore()
    }

    func schedule(descriptors: [AlarmScheduleDescriptor], now: Date) async -> AlarmSchedulingOutcome {
        #if canImport(AlarmKit) && canImport(SwiftUI) && !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            return await scheduleWithAlarmKit(descriptors: descriptors, now: now)
        }
        #endif
        store.save([])
        return AlarmSchedulingOutcome(fallbackItemIds: Set(descriptors.map(\.sourceItemId)))
    }

    #if canImport(AlarmKit) && canImport(SwiftUI) && !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    private func scheduleWithAlarmKit(
        descriptors: [AlarmScheduleDescriptor],
        now: Date
    ) async -> AlarmSchedulingOutcome {
        let previousIDs = store.load()
        let desiredIDs = Set(descriptors.map(\.id))
        let staleIDs = previousIDs.subtracting(desiredIDs)
        cancel(staleIDs)

        guard !descriptors.isEmpty else {
            store.save([])
            return AlarmSchedulingOutcome(fallbackItemIds: [])
        }

        guard await requestAuthorizationIfNeeded() else {
            cancel(desiredIDs)
            store.save([])
            return AlarmSchedulingOutcome(fallbackItemIds: Set(descriptors.map(\.sourceItemId)))
        }

        var successfulIDs = Set<UUID>()
        var fallbackItemIds = Set<String>()

        for descriptor in descriptors {
            do {
                let configuration = makeConfiguration(for: descriptor, now: now)
                _ = try await AlarmManager.shared.schedule(id: descriptor.id, configuration: configuration)
                successfulIDs.insert(descriptor.id)
            } catch {
                fallbackItemIds.insert(descriptor.sourceItemId)
            }
        }

        store.save(successfulIDs)
        return AlarmSchedulingOutcome(fallbackItemIds: fallbackItemIds)
    }

    @available(iOS 26.0, *)
    private func requestAuthorizationIfNeeded() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await manager.requestAuthorization() == .authorized
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    @available(iOS 26.0, *)
    private func cancel(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            try? AlarmManager.shared.cancel(id: id)
        }
    }

    @available(iOS 26.0, *)
    private func makeConfiguration(
        for descriptor: AlarmScheduleDescriptor,
        now: Date
    ) -> AlarmManager.AlarmConfiguration<NotificationAlarmMetadata> {
        let stopButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: "Ferma"),
            textColor: .white,
            systemImageName: "stop.fill"
        )

        let secondaryButton: AlarmButton?
        let secondaryBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior?
        let countdownDuration: Alarm.CountdownDuration?
        if let snoozeMinutes = descriptor.snoozeMinutes {
            secondaryButton = AlarmButton(
                text: LocalizedStringResource(stringLiteral: "Rimanda"),
                textColor: .white,
                systemImageName: "zzz"
            )
            secondaryBehavior = .countdown
            countdownDuration = Alarm.CountdownDuration(
                preAlert: nil,
                postAlert: TimeInterval(max(1, snoozeMinutes) * 60)
            )
        } else {
            secondaryButton = nil
            secondaryBehavior = nil
            countdownDuration = nil
        }

        let title = "\(descriptor.title). \(descriptor.body)"
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stopButton,
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryBehavior
            )
        )

        let metadata = NotificationAlarmMetadata(
            kind: descriptor.kind.rawValue,
            sourceItemId: descriptor.sourceItemId
        )
        let attributes = AlarmAttributes<NotificationAlarmMetadata>(
            presentation: presentation,
            metadata: metadata,
            tintColor: tintColor(for: descriptor.kind)
        )
        let fireDate = descriptor.date > now ? descriptor.date : now.addingTimeInterval(1)
        return AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default
        )
    }

    @available(iOS 26.0, *)
    private func tintColor(for kind: NotificationPlanKind) -> Color {
        switch kind {
        case .therapy:
            return .red
        case .stockLow, .stockOut:
            return .orange
        }
    }
    #endif
}

private protocol AlarmScheduledIDsStore {
    func load() -> Set<UUID>
    func save(_ ids: Set<UUID>)
}

private final class UserDefaultsAlarmScheduledIDsStore: AlarmScheduledIDsStore {
    private let defaults: UserDefaults
    private let key = "notification.alarmkit.scheduled.ids.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Set<UUID> {
        guard let stored = defaults.array(forKey: key) as? [String] else {
            return []
        }
        return Set(stored.compactMap(UUID.init(uuidString:)))
    }

    func save(_ ids: Set<UUID>) {
        defaults.set(ids.map(\.uuidString), forKey: key)
    }
}

#if canImport(AlarmKit) && canImport(SwiftUI) && !targetEnvironment(macCatalyst)
@available(iOS 26.0, *)
private struct NotificationAlarmMetadata: AlarmMetadata {
    let kind: String
    let sourceItemId: String
}
#endif
