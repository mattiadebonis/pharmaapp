import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

enum CriticalDoseActivityDismissalPolicy: Equatable {
    case immediate
    case at(Date)
}

protocol CriticalDoseLiveActivityClientProtocol {
    func currentActivityIDs() -> [String]
    func request(
        attributes: CriticalDoseLiveActivityAttributes,
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        staleDate: Date?
    ) async throws -> String
    func update(
        activityID: String,
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        staleDate: Date?
    ) async
    func end(
        activityID: String,
        dismissalPolicy: CriticalDoseActivityDismissalPolicy
    ) async
}

final class CriticalDoseLiveActivityClient: CriticalDoseLiveActivityClientProtocol {
    func currentActivityIDs() -> [String] {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return [] }
            return
            Activity<CriticalDoseLiveActivityAttributes>.activities.map { $0.id }
        }
        #endif
        return []
    }

    func request(
        attributes: CriticalDoseLiveActivityAttributes,
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        staleDate: Date?
    ) async throws -> String {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                throw NSError(domain: "CriticalDoseLiveActivityClient", code: 2)
            }
        }

        if #available(iOS 16.2, *) {
            let activity = try Activity<CriticalDoseLiveActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: staleDate),
                pushType: nil
            )
            return activity.id
        }

        if #available(iOS 16.1, *) {
            let activity = try Activity<CriticalDoseLiveActivityAttributes>.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
            return activity.id
        }
        #endif

        throw NSError(domain: "CriticalDoseLiveActivityClient", code: 1)
    }

    func update(
        activityID: String,
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let activity = Activity<CriticalDoseLiveActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
            return
        }

        if #available(iOS 16.2, *) {
            await activity.update(.init(state: contentState, staleDate: staleDate))
        } else {
            await activity.update(using: contentState)
        }
        #endif
    }

    func end(
        activityID: String,
        dismissalPolicy: CriticalDoseActivityDismissalPolicy
    ) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let activity = Activity<CriticalDoseLiveActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
            return
        }

        if #available(iOS 16.2, *) {
            let policy: ActivityUIDismissalPolicy
            switch dismissalPolicy {
            case .immediate:
                policy = .immediate
            case .at(let date):
                policy = .after(date)
            }
            await activity.end(nil, dismissalPolicy: policy)
        } else {
            await activity.end(dismissalPolicy: .immediate)
        }
        #endif
    }
}
