import Foundation

@MainActor
enum NotificationsGatewayBridge {
    static var gateway: any NotificationsGateway {
        if let provider = AppDataProviderRegistry.shared.provider {
            return provider.notifications
        }
        return legacyGateway
    }

    private static let legacyGateway: any NotificationsGateway = LegacyNotificationsGateway()
}

@MainActor
private final class LegacyNotificationsGateway: NotificationsGateway {
    private let actionPerformer: CriticalDoseActionPerforming = CriticalDoseActionService.shared
    private let liveActivityRefresher: CriticalDoseLiveActivityRefreshing = CriticalDoseLiveActivityCoordinator.shared

    func start() {}

    func refreshAfterStoreChange(reason: String) {
        let _ = reason
    }

    func refreshCriticalLiveActivity(reason: String, now: Date?) async {
        _ = await liveActivityRefresher.refresh(reason: reason, now: now)
    }

    func markCriticalDoseTaken(contentState: CriticalDoseLiveActivityAttributes.ContentState) -> Bool {
        actionPerformer.markTaken(contentState: contentState)
    }

    func remindCriticalDoseLater(contentState: CriticalDoseLiveActivityAttributes.ContentState, now: Date) async -> Bool {
        await actionPerformer.remindLater(contentState: contentState, now: now)
    }

    func showCriticalDoseConfirmationThenRefresh(medicineName: String) async {
        await liveActivityRefresher.showConfirmationThenRefresh(medicineName: medicineName)
    }
}
