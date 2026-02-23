import Foundation

@MainActor
final class LiveActivityURLActionHandler {
    static let shared = LiveActivityURLActionHandler()

    private enum QueryKey {
        static let action = "action"
        static let therapyId = "therapyId"
        static let medicineId = "medicineId"
        static let medicineName = "medicineName"
        static let doseText = "doseText"
        static let scheduledAt = "scheduledAt"
    }

    private enum Action: String {
        case markTaken = "mark-taken"
        case remindLater = "remind-later"
        case openPurchaseList = "open-purchase-list"
        case openHealthCard = "open-health-card"
        case dismissRefill = "dismiss-refill"
    }

    private let actionPerformer: CriticalDoseActionPerforming
    private let liveActivityRefresher: CriticalDoseLiveActivityRefreshing
    private let routeStore: PendingAppRouteStoring
    private let refillDismissHandler: RefillLiveActivityDismissHandling
    private let config: CriticalDoseLiveActivityConfig

    init(
        actionPerformer: CriticalDoseActionPerforming? = nil,
        liveActivityRefresher: CriticalDoseLiveActivityRefreshing? = nil,
        routeStore: PendingAppRouteStoring = PendingAppRouteStore(),
        refillDismissHandler: RefillLiveActivityDismissHandling? = nil,
        config: CriticalDoseLiveActivityConfig = .default
    ) {
        self.actionPerformer = actionPerformer ?? CriticalDoseActionService.shared
        self.liveActivityRefresher = liveActivityRefresher ?? CriticalDoseLiveActivityCoordinator.shared
        self.routeStore = routeStore
        self.refillDismissHandler = refillDismissHandler ?? RefillLiveActivityCoordinator.shared
        self.config = config
    }

    func handle(url: URL, now: Date = Date()) async -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "pharmaapp" else { return false }
        guard let host = url.host?.lowercased(), host == "live-activity" else { return false }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return true }
        var queryValues: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            queryValues[item.name] = value
        }

        guard let actionRaw = queryValues[QueryKey.action],
              let action = Action(rawValue: actionRaw) else {
            return true
        }

        switch action {
        case .markTaken:
            guard let state = makeState(from: queryValues) else { return true }
            let success = actionPerformer.markTaken(contentState: state)
            if success {
                await liveActivityRefresher.showConfirmationThenRefresh(medicineName: state.primaryMedicineName)
            } else {
                _ = await liveActivityRefresher.refresh(reason: "url-\(action.rawValue)", now: nil)
            }
        case .remindLater:
            guard let state = makeState(from: queryValues) else { return true }
            _ = await actionPerformer.remindLater(contentState: state, now: now)
            _ = await liveActivityRefresher.refresh(reason: "url-\(action.rawValue)", now: nil)
        case .openPurchaseList:
            routeStore.save(route: .pharmacy)
        case .openHealthCard:
            routeStore.save(route: .codiceFiscaleFullscreen)
        case .dismissRefill:
            await refillDismissHandler.dismissCurrentActivity(reason: "url-dismiss-refill")
        }

        return true
    }

    private func makeState(from queryValues: [String: String]) -> CriticalDoseLiveActivityAttributes.ContentState? {
        guard let therapyId = queryValues[QueryKey.therapyId], !therapyId.isEmpty else { return nil }
        guard let medicineId = queryValues[QueryKey.medicineId], !medicineId.isEmpty else { return nil }
        guard let medicineName = queryValues[QueryKey.medicineName], !medicineName.isEmpty else { return nil }
        guard let doseText = queryValues[QueryKey.doseText], !doseText.isEmpty else { return nil }
        guard let scheduledAtRaw = queryValues[QueryKey.scheduledAt],
              let scheduledAt = Self.dateFormatter.date(from: scheduledAtRaw) else {
            return nil
        }

        let subtitle = "\(medicineName) · \(doseText)"
        return CriticalDoseLiveActivityAttributes.ContentState(
            primaryTherapyId: therapyId,
            primaryMedicineId: medicineId,
            primaryMedicineName: medicineName,
            primaryDoseText: doseText,
            primaryScheduledAt: scheduledAt,
            additionalCount: 0,
            subtitleDisplay: subtitle,
            expiryAt: scheduledAt.addingTimeInterval(config.overdueToleranceInterval)
        )
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
