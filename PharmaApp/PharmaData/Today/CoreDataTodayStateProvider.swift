import Foundation
import CoreData

struct CoreDataTodayStateProvider {
    private let snapshotBuilder: CoreDataTodaySnapshotBuilder
    private let clock: Clock
    private let calendar: Calendar

    init(
        context: NSManagedObjectContext,
        clock: Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.snapshotBuilder = CoreDataTodaySnapshotBuilder(context: context)
        self.clock = clock
        self.calendar = calendar
    }

    func buildState(
        medicines: [Medicine],
        logs: [Log],
        option: Option?,
        completedTodoIDs: Set<String>
    ) -> TodayState {
        let now = clock.now()
        let input = snapshotBuilder.makeInput(
            medicines: medicines,
            logs: logs,
            option: option,
            completedTodoIDs: completedTodoIDs,
            now: now,
            calendar: calendar
        )
        return TodayStateBuilder.buildState(input: input)
    }

    func todoTimeDate(
        for item: TodayTodoItem,
        medicines: [Medicine],
        option: Option?,
        now: Date? = nil
    ) -> Date? {
        let resolvedNow = now ?? clock.now()
        let medicineSnapshots = snapshotBuilder.makeMedicineSnapshots(medicines: medicines, logs: [])
        let optionSnapshot = snapshotBuilder.makeOptionSnapshot(option: option)
        return TodayStateBuilder.todoTimeDate(
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
        return TodayStateBuilder.nextUpcomingDoseDate(
            for: snapshot,
            now: resolvedNow,
            calendar: calendar
        )
    }

    func nextDoseTodayInfo(
        for medicine: Medicine,
        option: Option?,
        now: Date? = nil
    ) -> TodayDoseInfo? {
        let resolvedNow = now ?? clock.now()
        let snapshot = snapshotBuilder.makeMedicineSnapshot(medicine: medicine, logs: Array(medicine.logs ?? []))
        let optionSnapshot = snapshotBuilder.makeOptionSnapshot(option: option)
        return TodayStateBuilder.nextDoseTodayInfo(
            for: snapshot,
            option: optionSnapshot,
            now: resolvedNow,
            calendar: calendar
        )
    }
}
