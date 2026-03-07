import Foundation

@MainActor
final class GatewayCriticalDoseActionPerformer: CriticalDoseActionPerforming {
    func markTaken(contentState: CriticalDoseLiveActivityAttributes.ContentState) -> Bool {
        NotificationsGatewayBridge.gateway.markCriticalDoseTaken(contentState: contentState)
    }

    func remindLater(contentState: CriticalDoseLiveActivityAttributes.ContentState, now: Date) async -> Bool {
        await NotificationsGatewayBridge.gateway.remindCriticalDoseLater(contentState: contentState, now: now)
    }
}

@MainActor
final class GatewayCriticalDoseLiveActivityRefresher: CriticalDoseLiveActivityRefreshing {
    func refresh(reason: String, now: Date?) async -> Date? {
        await NotificationsGatewayBridge.gateway.refreshCriticalLiveActivity(reason: reason, now: now)
        return nil
    }

    func showConfirmationThenRefresh(medicineName: String) async {
        await NotificationsGatewayBridge.gateway.showCriticalDoseConfirmationThenRefresh(medicineName: medicineName)
    }
}
