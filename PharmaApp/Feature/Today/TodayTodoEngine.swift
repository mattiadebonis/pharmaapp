import Foundation
import CoreData

@available(*, deprecated, message: "Use TodayStateBuilder + CoreDataTodayStateProvider.")
enum TodayTodoEngine {
    static func buildState(
        medicines: [Medicine],
        logs: [Log],
        todos: [Todo],
        option: Option?,
        completedTodoIDs: Set<String>,
        recurrenceManager: RecurrenceManager,
        clinicalContext: ClinicalContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayState {
        let context = recurrenceManager.context ?? medicines.first?.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let snapshotBuilder = CoreDataTodaySnapshotBuilder(context: context)
        let input = snapshotBuilder.makeInput(
            medicines: medicines,
            logs: logs,
            todos: todos,
            option: option,
            completedTodoIDs: completedTodoIDs,
            now: now,
            calendar: calendar
        )
        return TodayStateBuilder.buildState(input: input)
    }

    static func completionKey(for item: TodayTodoItem) -> String {
        TodayStateBuilder.completionKey(for: item)
    }

    static func syncToken(for items: [TodayTodoItem]) -> String {
        TodayStateBuilder.syncToken(for: items)
    }

    static func timeSortValue(
        for item: TodayTodoItem,
        medicines: [Medicine],
        option: Option?,
        recurrenceManager: RecurrenceManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        _ = medicines
        _ = option
        _ = recurrenceManager
        _ = now

        if (item.category == .monitoring || item.category == .missedDose),
           let date = timestampFromID(item) {
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
        if item.category == .deadline {
            return nil
        }
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        return (match.hour * 60) + match.minute
    }

    static func needsPrescriptionBeforePurchase(
        _ medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> Bool {
        let (snapshot, optionSnapshot) = makeSnapshot(medicine: medicine, option: option, recurrenceManager: recurrenceManager)
        return TodayStateBuilder.needsPrescriptionBeforePurchase(
            snapshot,
            option: optionSnapshot,
            now: Date(),
            calendar: .current
        )
    }

    static func isOutOfStock(
        _ medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> Bool {
        let (snapshot, optionSnapshot) = makeSnapshot(medicine: medicine, option: option, recurrenceManager: recurrenceManager)
        return TodayStateBuilder.isOutOfStock(
            snapshot,
            option: optionSnapshot,
            now: Date(),
            calendar: .current
        )
    }

    private static func makeSnapshot(
        medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> (MedicineSnapshot, OptionSnapshot?) {
        let context = recurrenceManager.context ?? medicine.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let snapshotBuilder = CoreDataTodaySnapshotBuilder(context: context)
        let snapshot = snapshotBuilder.makeMedicineSnapshot(medicine: medicine, logs: Array(medicine.logs ?? []))
        let optionSnapshot = snapshotBuilder.makeOptionSnapshot(option: option)
        return (snapshot, optionSnapshot)
    }

    private static func timestampFromID(_ item: TodayTodoItem) -> Date? {
        let parts = item.id.split(separator: "|")
        guard let last = parts.last, let seconds = TimeInterval(String(last)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func timeComponents(from detail: String) -> (hour: Int, minute: Int)? {
        let pattern = "([0-9]{1,2}):([0-9]{2})"
        guard let range = detail.range(of: pattern, options: .regularExpression) else { return nil }
        let substring = String(detail[range])
        let parts = substring.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let hour = parts[0]
        let minute = parts[1]
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}
