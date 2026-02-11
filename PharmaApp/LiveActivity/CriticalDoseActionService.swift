import Foundation
import CoreData

@MainActor
protocol CriticalDoseActionPerforming {
    func markTaken(contentState: CriticalDoseLiveActivityAttributes.ContentState) -> Bool
    func remindLater(contentState: CriticalDoseLiveActivityAttributes.ContentState, now: Date) async -> Bool
}

@MainActor
final class CriticalDoseActionService: CriticalDoseActionPerforming {
    static let shared = CriticalDoseActionService(
        context: PersistenceController.shared.container.viewContext
    )

    private let context: NSManagedObjectContext
    private let medicineActionService: MedicineActionService
    private let snoozeStore: CriticalDoseSnoozeStoreProtocol
    private let reminderScheduler: CriticalDoseReminderScheduling
    private let operationIdProvider: OperationIdProviding
    private let config: CriticalDoseLiveActivityConfig

    init(
        context: NSManagedObjectContext,
        medicineActionService: MedicineActionService? = nil,
        snoozeStore: CriticalDoseSnoozeStoreProtocol = CriticalDoseSnoozeStore(),
        reminderScheduler: CriticalDoseReminderScheduling = CriticalDoseReminderScheduler(),
        operationIdProvider: OperationIdProviding = OperationIdProvider.shared,
        config: CriticalDoseLiveActivityConfig = .default
    ) {
        self.context = context
        self.medicineActionService = medicineActionService ?? MedicineActionService(context: context)
        self.snoozeStore = snoozeStore
        self.reminderScheduler = reminderScheduler
        self.operationIdProvider = operationIdProvider
        self.config = config
    }

    func markTaken(contentState: CriticalDoseLiveActivityAttributes.ContentState) -> Bool {
        guard let therapyID = UUID(uuidString: contentState.primaryTherapyId) else { return false }
        guard let therapy = fetchTherapy(id: therapyID) else { return false }

        let operationKey = OperationKey.liveActivityIntake(
            therapyId: therapy.id,
            scheduledAt: contentState.primaryScheduledAt
        )
        let operationId = operationIdProvider.operationId(for: operationKey, ttl: 24 * 60 * 60)
        let log = medicineActionService.markAsTaken(for: therapy, operationId: operationId)
        if log == nil {
            operationIdProvider.clear(operationKey)
            return false
        }

        snoozeStore.clear(therapyId: therapy.id, scheduledAt: contentState.primaryScheduledAt)
        return true
    }

    @discardableResult
    func remindLater(
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        now: Date = Date()
    ) async -> Bool {
        guard let therapyID = UUID(uuidString: contentState.primaryTherapyId) else { return false }
        let remindAt = snoozeStore.snooze(
            therapyId: therapyID,
            scheduledAt: contentState.primaryScheduledAt,
            now: now,
            duration: config.snoozeInterval
        )
        await reminderScheduler.scheduleReminder(
            contentState: contentState,
            remindAt: remindAt,
            now: now
        )
        return true
    }

    private func fetchTherapy(id: UUID) -> Therapy? {
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }
}
