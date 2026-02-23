import Foundation
import CoreData

struct CoreDataTherapyPlanProvider {
    private let snapshotBuilder: CoreDataSnapshotBuilder
    private let clock: Clock
    private let calendar: Calendar

    init(
        context: NSManagedObjectContext,
        clock: Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.snapshotBuilder = CoreDataSnapshotBuilder(context: context)
        self.clock = clock
        self.calendar = calendar
    }

    func buildState(
        medicines: [Medicine],
        logs: [Log],
        option: Option?,
        completedTodoIDs: Set<String>
    ) -> TherapyPlanState {
        let now = clock.now()
        let input = snapshotBuilder.makeInput(
            medicines: medicines,
            logs: logs,
            option: option,
            completedTodoIDs: completedTodoIDs,
            now: now,
            calendar: calendar
        )
        return TherapyPlanBuilder.buildState(input: input)
    }

    func todoTimeDate(
        for item: TodoItem,
        medicines: [Medicine],
        option: Option?,
        now: Date? = nil
    ) -> Date? {
        let resolvedNow = now ?? clock.now()
        let medicineSnapshots = snapshotBuilder.makeMedicineSnapshots(medicines: medicines, logs: [])
        let optionSnapshot = snapshotBuilder.makeOptionSnapshot(option: option)
        return TherapyPlanBuilder.todoTimeDate(
            for: item,
            medicines: medicineSnapshots,
            option: optionSnapshot,
            now: resolvedNow,
            calendar: calendar
        )
    }

    func nextUpcomingDoseDate(
        for medicine: Medicine,
        now: Date? = nil
    ) -> Date? {
        let resolvedNow = now ?? clock.now()
        let snapshot = snapshotBuilder.makeMedicineSnapshot(medicine: medicine, logs: Array(medicine.logs ?? []))
        return TherapyPlanBuilder.nextUpcomingDoseDate(
            for: snapshot,
            now: resolvedNow,
            calendar: calendar
        )
    }

    func nextDoseTodayInfo(
        for medicine: Medicine,
        option: Option?,
        now: Date? = nil
    ) -> DoseInfo? {
        let resolvedNow = now ?? clock.now()
        let snapshot = snapshotBuilder.makeMedicineSnapshot(medicine: medicine, logs: Array(medicine.logs ?? []))
        let optionSnapshot = snapshotBuilder.makeOptionSnapshot(option: option)
        return TherapyPlanBuilder.nextDoseTodayInfo(
            for: snapshot,
            option: optionSnapshot,
            now: resolvedNow,
            calendar: calendar
        )
    }
}
