import Foundation
import CoreData
import UIKit

@MainActor
final class NotificationCoordinator: ObservableObject {
    private let context: NSManagedObjectContext
    private let scheduler: NotificationScheduler
    private var didStart = false
    private var debounceTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(
        context: NSManagedObjectContext,
        scheduler: NotificationScheduler? = nil
    ) {
        self.context = context
        if let scheduler {
            self.scheduler = scheduler
        } else {
            self.scheduler = NotificationScheduler(context: context)
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
            await self.scheduler.rescheduleAll(reason: reason)
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
        case is Therapy, is Dose, is Stock, is Log, is Medicine, is MedicinePackage, is Package:
            return true
        default:
            return false
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
