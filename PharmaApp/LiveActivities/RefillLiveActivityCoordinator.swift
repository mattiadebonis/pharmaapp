import Foundation
import CoreData
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
protocol RefillLiveActivityRefreshing: AnyObject {
    func refresh(reason: String, now: Date?) async
}

@MainActor
protocol RefillLiveActivityDismissHandling: AnyObject {
    func dismissCurrentActivity(reason: String) async
}

@MainActor
final class RefillLiveActivityCoordinator: NSObject, RefillLiveActivityRefreshing, RefillLiveActivityDismissHandling {
    static let shared = RefillLiveActivityCoordinator(
        context: PersistenceController.shared.container.viewContext,
        policy: PerformancePolicy.current()
    )

    private let context: NSManagedObjectContext
    private let purchaseSummaryProvider: RefillPurchaseSummaryProvider
    private let geofenceManager: RefillGeofenceManaging
    private let hoursResolver: RefillPharmacyHoursResolving
    private let stateStore: RefillActivityStateStoring
    private let client: RefillLiveActivityClientProtocol
    private let clock: Clock
    private let timeoutInterval: TimeInterval
    private let policy: PerformancePolicy

    private var didStart = false
    private var observers: [NSObjectProtocol] = []
    private var timeoutTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var debouncedRefreshTask: Task<Void, Never>?
    private var queuedRefreshReason: String?
    private var queuedRefreshNow: Date?

    init(
        context: NSManagedObjectContext,
        purchaseSummaryProvider: RefillPurchaseSummaryProvider? = nil,
        geofenceManager: RefillGeofenceManaging? = nil,
        hoursResolver: RefillPharmacyHoursResolving = RefillPharmacyHoursResolver(),
        stateStore: RefillActivityStateStoring = UserDefaultsRefillActivityStateStore(),
        client: RefillLiveActivityClientProtocol = RefillLiveActivityClient(),
        clock: Clock = SystemClock(),
        timeoutInterval: TimeInterval = 90 * 60,
        policy: PerformancePolicy = .foregroundInteractive
    ) {
        self.context = context
        self.purchaseSummaryProvider = purchaseSummaryProvider ?? RefillPurchaseSummaryProvider(context: context)
        self.geofenceManager = geofenceManager ?? RefillGeofenceManager(hoursResolver: hoursResolver, clock: clock)
        self.hoursResolver = hoursResolver
        self.stateStore = stateStore
        self.client = client
        self.clock = clock
        self.timeoutInterval = timeoutInterval
        self.policy = policy
        super.init()

        self.geofenceManager.onCandidateEntered = { [weak self] candidate in
            guard let self else { return }
            Task { @MainActor in
                await self.handleCandidateEntered(candidate)
            }
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange,
                object: context,
                queue: nil
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleContextChange(notification)
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleDebouncedRefresh(
                        reason: "foreground",
                        now: nil,
                        delayNanoseconds: self?.policy == .foregroundInteractive ? 1_500_000_000 : 350_000_000
                    )
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleDebouncedRefresh(
                        reason: "active",
                        now: nil,
                        delayNanoseconds: self?.policy == .foregroundInteractive ? 1_500_000_000 : 350_000_000
                    )
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.significantTimeChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleDebouncedRefresh(
                        reason: "time-change",
                        now: nil,
                        delayNanoseconds: self?.policy == .foregroundInteractive ? 2_000_000_000 : 350_000_000
                    )
                }
            }
        )

        geofenceManager.start()
        requestRefresh(reason: "startup", now: nil)
    }

    func refresh(reason: String, now: Date? = nil) async {
        let _ = reason
        let now = now ?? clock.now()

        let summary = purchaseSummaryProvider.summary(
            maxVisible: 3,
            strategy: policy == .foregroundInteractive ? .lightweightTodos : .fullTodayState
        )
        geofenceManager.refreshMonitoring(hasPendingPurchases: summary.hasItems)

        guard summary.hasItems else {
            await endActiveActivity(reason: "no-purchases")
            return
        }

        guard liveActivitiesEnabled else {
            await endActiveActivity(reason: "disabled")
            return
        }

        if let startedAt = stateStore.activeStartedAt(), now.timeIntervalSince(startedAt) >= timeoutInterval {
            await endActiveActivity(reason: "timeout")
            return
        }

        guard let activityId = stateStore.activeActivityId(),
              let pharmacyId = stateStore.activePharmacyId(),
              let candidate = geofenceManager.candidate(for: pharmacyId) else {
            scheduleTimeoutIfNeeded()
            return
        }

        let openInfo = hoursResolver.openInfo(forPharmacyName: candidate.name, now: now)
        guard openInfo.isOpen else {
            await endActiveActivity(reason: "pharmacy-closed")
            return
        }

        let state = makeContentState(candidate: candidate, summary: summary, now: now)
        await client.update(activityID: activityId, contentState: state, staleDate: now.addingTimeInterval(timeoutInterval))
        scheduleTimeoutIfNeeded()
    }

    func dismissCurrentActivity(reason: String) async {
        let _ = reason
        await endActiveActivity(reason: "dismiss")
    }

    private func handleContextChange(_ notification: Notification) {
        guard hasRelevantChanges(notification) else { return }
        if policy == .foregroundInteractive {
            scheduleDebouncedRefresh(reason: "core-data", now: nil, delayNanoseconds: 2_500_000_000)
        } else {
            requestRefresh(reason: "core-data", now: nil)
        }
    }

    private func hasRelevantChanges(_ notification: Notification) -> Bool {
        let keys: [String] = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]

        for key in keys {
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: isRelevantManagedObject(_:)) {
                return true
            }
        }

        return false
    }

    private func isRelevantManagedObject(_ object: NSManagedObject) -> Bool {
        switch object {
        case is Therapy, is Dose, is Stock, is Log, is Medicine, is MedicinePackage, is Package, is Option, is Todo:
            return true
        default:
            return false
        }
    }

    private func handleCandidateEntered(_ candidate: RefillPharmacyCandidate) async {
        guard liveActivitiesEnabled else { return }

        let now = clock.now()
        let summary = purchaseSummaryProvider.summary(
            maxVisible: 3,
            strategy: policy == .foregroundInteractive ? .lightweightTodos : .fullTodayState
        )
        guard summary.hasItems else {
            await endActiveActivity(reason: "entered-no-purchases")
            return
        }

        let openInfo = hoursResolver.openInfo(forPharmacyName: candidate.name, now: now)
        guard openInfo.isOpen else { return }

        let activeActivityId = stateStore.activeActivityId()
        let activePharmacyId = stateStore.activePharmacyId()

        if activeActivityId != nil, activePharmacyId == candidate.id {
            let state = makeContentState(candidate: candidate, summary: summary, now: now)
            if let activeActivityId {
                await client.update(
                    activityID: activeActivityId,
                    contentState: state,
                    staleDate: now.addingTimeInterval(timeoutInterval)
                )
                scheduleTimeoutIfNeeded()
            }
            return
        }

        guard stateStore.canShow(for: candidate.id, now: now) else { return }

        if activeActivityId != nil {
            await endActiveActivity(reason: "switch-pharmacy")
        }

        let attributes = RefillActivityAttributes(
            pharmacyId: candidate.id,
            pharmacyName: candidate.name,
            latitude: candidate.latitude,
            longitude: candidate.longitude
        )
        let state = makeContentState(candidate: candidate, summary: summary, now: now)

        do {
            let id = try await client.request(
                attributes: attributes,
                contentState: state,
                staleDate: now.addingTimeInterval(timeoutInterval)
            )
            stateStore.markShown(for: candidate.id, activityId: id, startedAt: now, now: now)
            scheduleTimeoutIfNeeded()
        } catch {
            // Ignore transient ActivityKit failures; we'll retry on next enter/refresh.
        }
    }

    private func requestRefresh(reason: String, now: Date?) {
        if refreshTask != nil {
            queuedRefreshReason = reason
            queuedRefreshNow = now
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh(reason: reason, now: now)
            self.refreshTask = nil

            if let queuedReason = self.queuedRefreshReason {
                let queuedNow = self.queuedRefreshNow
                self.queuedRefreshReason = nil
                self.queuedRefreshNow = nil
                self.requestRefresh(reason: queuedReason, now: queuedNow)
            }
        }
    }

    private func scheduleDebouncedRefresh(
        reason: String,
        now: Date?,
        delayNanoseconds: UInt64
    ) {
        debouncedRefreshTask?.cancel()
        debouncedRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self else { return }
            self.requestRefresh(reason: reason, now: now)
        }
    }

    private func makeContentState(
        candidate: RefillPharmacyCandidate,
        summary: RefillPurchaseSummary,
        now: Date
    ) -> RefillActivityAttributes.ContentState {
        RefillActivityAttributes.ContentState(
            primaryText: "Farmacia aperta qui vicino",
            etaMinutes: candidate.etaMinutes,
            distanceMeters: candidate.distanceMeters,
            closingTimeText: candidate.closingTimeText,
            purchaseNames: summary.visibleNames,
            remainingPurchaseCount: summary.remainingCount,
            lastUpdatedAt: now,
            showHealthCardAction: true
        )
    }

    private func endActiveActivity(reason: String) async {
        let _ = reason
        timeoutTask?.cancel()
        timeoutTask = nil

        if let activityId = stateStore.activeActivityId() {
            await client.end(activityID: activityId, dismissalPolicy: .immediate)
        } else {
            for id in client.currentActivityIDs() {
                await client.end(activityID: id, dismissalPolicy: .immediate)
            }
        }
        stateStore.clearActive()
    }

    private func scheduleTimeoutIfNeeded() {
        timeoutTask?.cancel()
        guard let startedAt = stateStore.activeStartedAt() else { return }

        let fireDate = startedAt.addingTimeInterval(timeoutInterval)
        let now = clock.now()
        let delay = fireDate.timeIntervalSince(now)

        if delay <= 0 {
            timeoutTask = Task { @MainActor [weak self] in
                await self?.dismissCurrentActivity(reason: "timeout-immediate")
            }
            return
        }

        timeoutTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await self?.dismissCurrentActivity(reason: "timeout")
        }
    }

    private var liveActivitiesEnabled: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
        return false
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        timeoutTask?.cancel()
        refreshTask?.cancel()
        debouncedRefreshTask?.cancel()
    }
}
