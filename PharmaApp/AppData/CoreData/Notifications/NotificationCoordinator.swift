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
        policy: PerformancePolicy = .foregroundInteractive,
        scheduler: NotificationScheduler? = nil,
        autoIntakeProcessor: AutoIntakeProcessor? = nil,
        liveActivityCoordinator: CriticalDoseLiveActivityCoordinator? = nil,
        container: NSPersistentContainer = PersistenceController.shared.container
    ) {
        self.policy = policy
        self.scheduler = scheduler
        self.autoIntakeProcessor = autoIntakeProcessor
        if let liveActivityCoordinator {
            self.liveActivityCoordinator = liveActivityCoordinator
        } else {
            self.liveActivityCoordinator = CriticalDoseLiveActivityCoordinator(context: container.viewContext)
        }
        self.container = container
    }

    convenience init(
        policy: PerformancePolicy = .foregroundInteractive,
        scheduler: NotificationScheduler? = nil,
        autoIntakeProcessor: AutoIntakeProcessor? = nil
    ) {
        self.init(
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

    func refreshAfterStoreChange(reason: String = "backup-restore") {
        scheduleRefresh(reason: reason, debounceNanoseconds: 100_000_000)
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
            guard self.shouldRefreshCriticalLiveActivity(reason: "live-activity-checkpoint") else {
                self.liveActivityTask = nil
                return
            }
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
            return true
        }
    }

    private func shouldRefreshCriticalLiveActivity(reason: String) -> Bool {
        switch policy {
        case .fullAutomation:
            return true
        case .foregroundInteractive:
            if reason == "live-activity-checkpoint" {
                return UIApplication.shared.applicationState != .active
            }
            return reason == "startup"
                || reason == "background"
                || reason == "auto-intake"
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
