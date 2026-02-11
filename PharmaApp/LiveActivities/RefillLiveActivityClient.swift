import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

enum RefillActivityDismissalPolicy: Equatable {
    case immediate
    case defaultPolicy
}

protocol RefillLiveActivityClientProtocol {
    func currentActivityIDs() -> [String]
    func request(
        attributes: RefillActivityAttributes,
        contentState: RefillActivityAttributes.ContentState,
        staleDate: Date?
    ) async throws -> String
    func update(
        activityID: String,
        contentState: RefillActivityAttributes.ContentState,
        staleDate: Date?
    ) async
    func end(activityID: String, dismissalPolicy: RefillActivityDismissalPolicy) async
}

final class RefillLiveActivityClient: RefillLiveActivityClientProtocol {
    func currentActivityIDs() -> [String] {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return Activity<RefillActivityAttributes>.activities.map { $0.id }
        }
        #endif
        return []
    }

    func request(
        attributes: RefillActivityAttributes,
        contentState: RefillActivityAttributes.ContentState,
        staleDate: Date?
    ) async throws -> String {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let activity = try Activity<RefillActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: contentState, staleDate: staleDate),
                pushType: nil
            )
            return activity.id
        }
        if #available(iOS 16.1, *) {
            let activity = try Activity<RefillActivityAttributes>.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
            return activity.id
        }
        #endif
        throw NSError(domain: "RefillLiveActivityClient", code: 1)
    }

    func update(
        activityID: String,
        contentState: RefillActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = Activity<RefillActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
            return
        }
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: contentState, staleDate: staleDate))
        } else {
            await activity.update(using: contentState)
        }
        #endif
    }

    func end(activityID: String, dismissalPolicy: RefillActivityDismissalPolicy) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = Activity<RefillActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
            return
        }
        if #available(iOS 16.2, *) {
            let mapped: ActivityUIDismissalPolicy = dismissalPolicy == .immediate ? .immediate : .default
            await activity.end(nil, dismissalPolicy: mapped)
        } else {
            await activity.end(dismissalPolicy: dismissalPolicy == .immediate ? .immediate : .default)
        }
        #endif
    }
}
