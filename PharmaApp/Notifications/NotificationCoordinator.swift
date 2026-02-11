import Foundation
import CoreData
import UIKit

@MainActor
final class NotificationCoordinator: ObservableObject {
    private let context: NSManagedObjectContext
    private let scheduler: NotificationScheduler
    private let autoIntakeProcessor: AutoIntakeProcessor
    private let liveActivityCoordinator: CriticalDoseLiveActivityCoordinator
    private var didStart = false
    private var debounceTask: Task<Void, Never>?
    private var autoIntakeTask: Task<Void, Never>?
    private var liveActivityTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(
        context: NSManagedObjectContext,
        scheduler: NotificationScheduler? = nil,
        autoIntakeProcessor: AutoIntakeProcessor? = nil,
        liveActivityCoordinator: CriticalDoseLiveActivityCoordinator?
    ) {
        self.context = context
        if let scheduler {
            self.scheduler = scheduler
        } else {
            self.scheduler = NotificationScheduler(context: context)
        }
        if let autoIntakeProcessor {
            self.autoIntakeProcessor = autoIntakeProcessor
        } else {
            self.autoIntakeProcessor = AutoIntakeProcessor(context: context)
        }
        if let liveActivityCoordinator {
            self.liveActivityCoordinator = liveActivityCoordinator
        } else {
            self.liveActivityCoordinator = CriticalDoseLiveActivityCoordinator(context: context)
        }
    }

    convenience init(
        context: NSManagedObjectContext,
        scheduler: NotificationScheduler? = nil,
        autoIntakeProcessor: AutoIntakeProcessor? = nil
    ) {
        self.init(
            context: context,
            scheduler: scheduler,
            autoIntakeProcessor: autoIntakeProcessor,
            liveActivityCoordinator: nil
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
                    self?.scheduleRefresh(reason: "foreground")
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
                    self?.scheduleRefresh(reason: "active")
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
                    self?.scheduleRefresh(reason: "time-change")
                }
            }
        )

        scheduleRefresh(reason: "startup")
    }

    private func handleContextChange(_ notification: Notification) {
        guard hasRelevantChanges(notification) else { return }
        scheduleRefresh(reason: "core-data")
    }

    private func scheduleRefresh(reason: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            self.autoIntakeProcessor.processDueIntakes(now: Date())
            await self.scheduler.rescheduleAll(reason: reason)
            let nextLiveActivityRefresh = await self.liveActivityCoordinator.refresh(reason: reason)
            self.scheduleNextLiveActivityRefresh(nextDate: nextLiveActivityRefresh)
            self.scheduleNextAutoIntake()
        }
    }

    private func scheduleNextAutoIntake() {
        autoIntakeTask?.cancel()
        guard let nextDate = autoIntakeProcessor.nextAutoIntakeDate(now: Date()) else { return }
        let now = Date()
        let delaySeconds = max(1, nextDate.timeIntervalSince(now) + 1)
        autoIntakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self else { return }
            self.autoIntakeProcessor.processDueIntakes(now: Date())
            await self.scheduler.rescheduleAll(reason: "auto-intake")
            let nextLiveActivityRefresh = await self.liveActivityCoordinator.refresh(reason: "auto-intake")
            self.scheduleNextLiveActivityRefresh(nextDate: nextLiveActivityRefresh)
            self.scheduleNextAutoIntake()
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
    }
}
