import Foundation
import CoreData
import UIKit

enum PerformancePolicy: String {
    case foregroundInteractive
    case fullAutomation

    private static let userDefaultsKey = "performance_policy"
    private static let environmentKey = "PHARMA_PERFORMANCE_POLICY"

    static func current(
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) -> PerformancePolicy {
        if let raw = processInfo.environment[environmentKey],
           let policy = normalized(raw) {
            return policy
        }
        if let raw = userDefaults.string(forKey: userDefaultsKey),
           let policy = normalized(raw) {
            return policy
        }
        return .foregroundInteractive
    }

    private static func normalized(_ raw: String) -> PerformancePolicy? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "foregroundinteractive", "foreground_interactive", "interactive":
            return .foregroundInteractive
        case "fullautomation", "full_automation", "automation":
            return .fullAutomation
        default:
            return nil
        }
    }
}

@MainActor
final class NotificationCoordinator: ObservableObject {
    private let context: NSManagedObjectContext
    private let policy: PerformancePolicy
    private let scheduler: NotificationScheduler?
    private let autoIntakeProcessor: AutoIntakeProcessor?
    private let liveActivityCoordinator: CriticalDoseLiveActivityCoordinator
    private let container: NSPersistentContainer
    private var didStart = false
    private var debounceTask: Task<Void, Never>?
    private var autoIntakeTask: Task<Void, Never>?
    private var liveActivityTask: Task<Void, Never>?
    private var startupWarmupTask: Task<Void, Never>?
    private var refreshInFlight = false
    private var queuedRefreshReason: String?
    private var observers: [NSObjectProtocol] = []

    init(
        context: NSManagedObjectContext,
        policy: PerformancePolicy = .foregroundInteractive,
        scheduler: NotificationScheduler? = nil,
        autoIntakeProcessor: AutoIntakeProcessor? = nil,
        liveActivityCoordinator: CriticalDoseLiveActivityCoordinator?,
        container: NSPersistentContainer = PersistenceController.shared.container
    ) {
        self.context = context
        self.policy = policy
        self.scheduler = scheduler
        self.autoIntakeProcessor = autoIntakeProcessor
        if let liveActivityCoordinator {
            self.liveActivityCoordinator = liveActivityCoordinator
        } else {
            self.liveActivityCoordinator = CriticalDoseLiveActivityCoordinator(context: context)
        }
        self.container = container
    }

    convenience init(
        context: NSManagedObjectContext,
        policy: PerformancePolicy = .foregroundInteractive,
        scheduler: NotificationScheduler? = nil,
        autoIntakeProcessor: AutoIntakeProcessor? = nil
    ) {
        self.init(
            context: context,
            policy: policy,
            scheduler: scheduler,
            autoIntakeProcessor: autoIntakeProcessor,
            liveActivityCoordinator: nil,
            container: PersistenceController.shared.container
        )
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
                    self?.scheduleRefresh(
                        reason: "foreground",
                        debounceNanoseconds: self?.policy == .foregroundInteractive ? 1_200_000_000 : 500_000_000
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
                    self?.scheduleRefresh(
                        reason: "active",
                        debounceNanoseconds: self?.policy == .foregroundInteractive ? 1_200_000_000 : 500_000_000
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
                    self?.scheduleRefresh(
                        reason: "time-change",
                        debounceNanoseconds: self?.policy == .foregroundInteractive ? 1_200_000_000 : 500_000_000
                    )
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRefresh(reason: "background", debounceNanoseconds: 250_000_000)
                }
            }
        )

        if policy == .foregroundInteractive {
            startupWarmupTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self?.scheduleRefresh(reason: "startup", debounceNanoseconds: 100_000_000)
                }
            }
        } else {
            scheduleRefresh(reason: "startup", debounceNanoseconds: 100_000_000)
        }
    }

    private func handleContextChange(_ notification: Notification) {
        guard hasRelevantChanges(notification) else { return }
        let debounce: UInt64 = policy == .foregroundInteractive ? 1_800_000_000 : 500_000_000
        scheduleRefresh(reason: "core-data", debounceNanoseconds: debounce)
    }

    private func scheduleRefresh(reason: String, debounceNanoseconds: UInt64? = nil) {
        debounceTask?.cancel()
        let delay = debounceNanoseconds ?? 500_000_000
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self else { return }
            if self.refreshInFlight {
                self.queuedRefreshReason = reason
                return
            }
            self.refreshInFlight = true
            defer {
                self.refreshInFlight = false
                if let queued = self.queuedRefreshReason {
                    self.queuedRefreshReason = nil
                    self.scheduleRefresh(reason: queued, debounceNanoseconds: 200_000_000)
                }
            }
            let now = Date()
            if self.shouldRunAutoIntake(reason: reason) {
                await self.runAutoIntake(now: now)
            }

            await self.rescheduleNotifications(reason: reason)

            if self.shouldRefreshCriticalLiveActivity(reason: reason) {
                let nextLiveActivityRefresh = await self.liveActivityCoordinator.refresh(reason: reason)
                self.scheduleNextLiveActivityRefresh(nextDate: nextLiveActivityRefresh)
            }
            if self.shouldMaintainAutoIntakeTimer() {
                self.scheduleNextAutoIntake()
            } else {
                self.autoIntakeTask?.cancel()
                self.autoIntakeTask = nil
            }
        }
    }

    private func scheduleNextAutoIntake() {
        autoIntakeTask?.cancel()
        let processor = autoIntakeProcessor ?? AutoIntakeProcessor(context: container.newBackgroundContext())
        guard let nextDate = processor.nextAutoIntakeDate(now: Date()) else { return }
        let now = Date()
        let delaySeconds = max(1, nextDate.timeIntervalSince(now) + 1)
        autoIntakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self else { return }
            if self.shouldRunAutoIntake(reason: "auto-intake") {
                await self.runAutoIntake(now: Date())
            }
            await self.rescheduleNotifications(reason: "auto-intake")
            if self.shouldRefreshCriticalLiveActivity(reason: "auto-intake") {
                let nextLiveActivityRefresh = await self.liveActivityCoordinator.refresh(reason: "auto-intake")
                self.scheduleNextLiveActivityRefresh(nextDate: nextLiveActivityRefresh)
            }
            if self.shouldMaintainAutoIntakeTimer() {
                self.scheduleNextAutoIntake()
            }
        }
    }

    private func scheduleNextLiveActivityRefresh(nextDate: Date?) {
        liveActivityTask?.cancel()
        guard let nextDate else { return }
        let now = Date()
        let delaySeconds = max(1, nextDate.timeIntervalSince(now) + 1)
        liveActivityTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self else { return }
            let next = await self.liveActivityCoordinator.refresh(reason: "live-activity-checkpoint")
            self.scheduleNextLiveActivityRefresh(nextDate: next)
        }
    }

    private func runAutoIntake(now: Date) async {
        let injectedProcessor = autoIntakeProcessor
        let container = self.container
        _ = await Task.detached(priority: .utility) {
            let processor = injectedProcessor ?? AutoIntakeProcessor(context: container.newBackgroundContext())
            return processor.processDueIntakesBatch(now: now, saveAtEnd: true)
        }.value
    }

    private func rescheduleNotifications(reason: String) async {
        let injectedScheduler = scheduler
        let container = self.container
        await Task.detached(priority: .utility) {
            let scheduler = injectedScheduler ?? NotificationScheduler(context: container.newBackgroundContext())
            await scheduler.rescheduleAll(reason: reason)
        }.value
    }

    private func shouldRunAutoIntake(reason: String) -> Bool {
        switch policy {
        case .fullAutomation:
            return true
        case .foregroundInteractive:
            return reason == "startup" || reason == "background" || reason == "auto-intake"
        }
    }

    private func shouldMaintainAutoIntakeTimer() -> Bool {
        switch policy {
        case .fullAutomation:
            return true
        case .foregroundInteractive:
            return UIApplication.shared.applicationState != .active
        }
    }

    private func shouldRefreshCriticalLiveActivity(reason: String) -> Bool {
        switch policy {
        case .fullAutomation:
            return true
        case .foregroundInteractive:
            return reason == "startup"
                || reason == "background"
                || reason == "auto-intake"
                || reason == "live-activity-checkpoint"
        }
    }

    private func hasRelevantChanges(_ notification: Notification) -> Bool {
        let keys: [String] = [
            NSInsertedObjectsKey,
            NSUpdatedObjectsKey,
            NSDeletedObjectsKey
        ]

        for key in keys {
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { isRelevant($0) }) {
                return true
            }
        }
        return false
    }

    private func isRelevant(_ object: NSManagedObject) -> Bool {
        switch object {
        case is Therapy, is Dose, is Stock, is Log, is Medicine, is MedicinePackage, is Package, is Option:
            return true
        default:
            return false
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        debounceTask?.cancel()
        autoIntakeTask?.cancel()
        liveActivityTask?.cancel()
        startupWarmupTask?.cancel()
    }
}
