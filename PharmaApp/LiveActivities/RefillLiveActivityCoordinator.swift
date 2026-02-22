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
    private let prescriptionCFResolver: PrescriptionCodiceFiscaleResolver
    private let stateStore: RefillActivityStateStoring
    private let client: RefillLiveActivityClientProtocol
    private let clock: Clock
    private let policy: PerformancePolicy

    private var didStart = false
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var debouncedRefreshTask: Task<Void, Never>?
    private var queuedRefreshReason: String?
    private var queuedRefreshNow: Date?

    init(
        context: NSManagedObjectContext,
        purchaseSummaryProvider: RefillPurchaseSummaryProvider? = nil,
        geofenceManager: RefillGeofenceManaging? = nil,
        hoursResolver: RefillPharmacyHoursResolving = RefillPharmacyHoursResolver(),
        prescriptionCFResolver: PrescriptionCodiceFiscaleResolver? = nil,
        stateStore: RefillActivityStateStoring = UserDefaultsRefillActivityStateStore(),
        client: RefillLiveActivityClientProtocol = RefillLiveActivityClient(),
        clock: Clock = SystemClock(),
        policy: PerformancePolicy = .foregroundInteractive
    ) {
        self.context = context
        self.purchaseSummaryProvider = purchaseSummaryProvider ?? RefillPurchaseSummaryProvider(context: context)
        self.geofenceManager = geofenceManager ?? RefillGeofenceManager(hoursResolver: hoursResolver, clock: clock)
        self.hoursResolver = hoursResolver
        self.prescriptionCFResolver = prescriptionCFResolver ?? PrescriptionCodiceFiscaleResolver()
        self.stateStore = stateStore
        self.client = client
        self.clock = clock
        self.policy = policy
        super.init()

        self.geofenceManager.onCandidateEntered = { [weak self] candidate in
            guard let self else { return }
            Task { @MainActor in
                await self.handleCandidateEntered(candidate)
            }
        }

        self.geofenceManager.onCandidatesUpdated = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleDebouncedRefresh(
                    reason: "pharmacy-candidates-updated",
                    now: nil,
                    delayNanoseconds: self.policy == .foregroundInteractive ? 1_000_000_000 : 300_000_000
                )
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

        let activePharmacyId = stateStore.activePharmacyId()
        let candidate = resolvedCandidate(activePharmacyId: activePharmacyId)
        if let candidate {
            await presentOrUpdateActivity(candidate: candidate, summary: summary, now: now)
        } else {
            await presentOrUpdateActivityWithoutPharmacy(summary: summary, now: now)
        }
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
        case is Therapy, is Dose, is Stock, is Log, is Medicine, is MedicinePackage, is Package, is Option, is Doctor:
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
        await presentOrUpdateActivity(candidate: candidate, summary: summary, now: now)
    }

    private static let noPharmacyId = "no-pharmacy"

    private func presentOrUpdateActivityWithoutPharmacy(
        summary: RefillPurchaseSummary,
        now: Date
    ) async {
        let noPharmacyId = Self.noPharmacyId
        let activeActivityId = stateStore.activeActivityId()
        let activePharmacyId = stateStore.activePharmacyId()

        if let activeActivityId, activePharmacyId == noPharmacyId {
            if client.currentActivityIDs().contains(activeActivityId) {
                // Update the existing no-pharmacy activity.
                let state = makeContentState(candidate: nil, summary: summary, now: now)
                await client.update(
                    activityID: activeActivityId,
                    contentState: state,
                    staleDate: nil
                )
                return
            }
            // Activity was ended externally (e.g. user dismissed from lock screen); clear and recreate.
            stateStore.clearActive()
        } else if let activeActivityId {
            if client.currentActivityIDs().contains(activeActivityId) {
                // A pharmacy activity is already running (pharmacy temporarily out of geofence range).
                // Keep it alive rather than replacing it with a no-pharmacy activity.
                return
            }
            // Stale entry for an activity that no longer exists; clean up and fall through to create.
            stateStore.clearActive()
        }

        let attributes = RefillActivityAttributes(
            pharmacyId: noPharmacyId,
            pharmacyName: "",
            latitude: 0,
            longitude: 0
        )
        let state = makeContentState(candidate: nil, summary: summary, now: now)

        do {
            let id = try await client.request(
                attributes: attributes,
                contentState: state,
                staleDate: nil
            )
            stateStore.markShown(for: noPharmacyId, activityId: id, startedAt: now, now: now)
        } catch {
            // Ignore transient ActivityKit failures; we'll retry on next refresh.
        }
    }

    private func presentOrUpdateActivity(
        candidate: RefillPharmacyCandidate,
        summary: RefillPurchaseSummary,
        now: Date
    ) async {
        let activeActivityId = stateStore.activeActivityId()
        let activePharmacyId = stateStore.activePharmacyId()

        if let activeActivityId, activePharmacyId == candidate.id {
            let state = makeContentState(candidate: candidate, summary: summary, now: now)
            await client.update(
                activityID: activeActivityId,
                contentState: state,
                staleDate: nil
            )
            return
        }

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
                staleDate: nil
            )
            stateStore.markShown(for: candidate.id, activityId: id, startedAt: now, now: now)
        } catch {
            // Ignore transient ActivityKit failures; we'll retry on next enter/refresh.
        }
    }

    private func resolvedCandidate(activePharmacyId: String?) -> RefillPharmacyCandidate? {
        if let activePharmacyId,
           let activeCandidate = geofenceManager.candidate(for: activePharmacyId) {
            return activeCandidate
        }
        return geofenceManager.nearestCandidate()
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
        candidate: RefillPharmacyCandidate?,
        summary: RefillPurchaseSummary,
        now: Date
    ) -> RefillActivityAttributes.ContentState {
        let pharmacyName = candidate?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedPharmacyName = pharmacyName.isEmpty ? "Farmacia più vicina" : pharmacyName

        let cfEntries = prescriptionCFResolver.entriesForRxAndLowStock(in: context).map {
            RefillActivityAttributes.CFDisplayEntry(
                personName: $0.personDisplayName,
                codiceFiscale: $0.codiceFiscale
            )
        }

        let distance = candidate?.distanceMeters ?? 0
        let isWalking = distance < 2000
        let openInfo = candidate.map { hoursResolver.openInfo(forPharmacyName: $0.name, now: now) }
        let isPharmacyOpen = openInfo?.isOpen ?? false

        return RefillActivityAttributes.ContentState(
            primaryText: "Scorte sotto soglia",
            pharmacyName: resolvedPharmacyName,
            etaMinutes: candidate?.etaMinutes ?? 0,
            distanceMeters: distance,
            pharmacyHoursText: openInfo.map { resolvedPharmacyHoursText(openInfo: $0, candidate: candidate!, now: now) } ?? "orari non disponibili",
            purchaseNames: summary.allNames,
            purchaseItems: summary.allItems,
            isWalking: isWalking,
            isPharmacyOpen: isPharmacyOpen,
            codiceFiscaleEntries: cfEntries,
            lastUpdatedAt: now
        )
    }

    private func resolvedPharmacyHoursText(openInfo: RefillPharmacyOpenInfo, candidate: RefillPharmacyCandidate, now: Date) -> String {
        let _ = now
        if let openText = openInfo.closingTimeText, openInfo.isOpen {
            return openText
        }
        if let slotText = openInfo.slotText?.trimmingCharacters(in: .whitespacesAndNewlines), !slotText.isEmpty {
            return "oggi \(slotText)"
        }
        return candidate.pharmacyHoursText
    }

    private func endActiveActivity(reason: String) async {
        let _ = reason

        if let activityId = stateStore.activeActivityId() {
            await client.end(activityID: activityId, dismissalPolicy: .immediate)
        } else {
            for id in client.currentActivityIDs() {
                await client.end(activityID: id, dismissalPolicy: .immediate)
            }
        }
        stateStore.clearActive()
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
        refreshTask?.cancel()
        debouncedRefreshTask?.cancel()
    }
}
