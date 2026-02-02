import XCTest
@testable import PharmaApp

final class TodayTodoEngineTests: XCTestCase {
    func testCompletionKeyUsesItemIDForMonitoringAndMissedDose() {
        let monitoring = TodayTodoItem(
            id: "monitoring|bp|systolic|123",
            title: "Monitoraggio",
            detail: nil,
            category: .monitoring,
            medicineID: nil
        )
        XCTAssertEqual(TodayTodoEngine.completionKey(for: monitoring), monitoring.id)

        let missed = TodayTodoItem(
            id: "missed|dose|123",
            title: "Dose mancata",
            detail: nil,
            category: .missedDose,
            medicineID: nil
        )
        XCTAssertEqual(TodayTodoEngine.completionKey(for: missed), missed.id)
    }

    func testSyncTokenChangesWhenDetailChanges() {
        let base = TodayTodoItem(
            id: "therapy|a",
            title: "Terapia",
            detail: "08:00",
            category: .therapy,
            medicineID: nil
        )
        let token1 = TodayTodoEngine.syncToken(for: [base])

        let updated = TodayTodoItem(
            id: "therapy|a",
            title: "Terapia",
            detail: "09:00",
            category: .therapy,
            medicineID: nil
        )
        let token2 = TodayTodoEngine.syncToken(for: [updated])

        XCTAssertNotEqual(token1, token2)
    }

    func testTimeSortValueForMonitoringUsesTimestampFromID() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2024,
            month: 1,
            day: 2,
            hour: 8,
            minute: 45
        ).date!
        let timestamp = Int(date.timeIntervalSince1970)

        let item = TodayTodoItem(
            id: "monitoring|bp|systolic|\(timestamp)",
            title: "Pressione",
            detail: nil,
            category: .monitoring,
            medicineID: nil
        )

        let sortValue = TodayTodoEngine.timeSortValue(
            for: item,
            medicines: [],
            option: nil,
            recurrenceManager: RecurrenceManager(context: nil),
            now: date,
            calendar: calendar
        )

        XCTAssertEqual(sortValue, 8 * 60 + 45)
    }
}
