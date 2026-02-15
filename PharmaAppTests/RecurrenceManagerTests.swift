import XCTest
import CoreData
@testable import PharmaApp

final class RecurrenceManagerTests: XCTestCase {
    func testParseRecurrenceStringReturnsEquivalentRuleForSameInput() {
        let manager = RecurrenceManager(context: nil)
        let raw = "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE"

        let first = manager.parseRecurrenceString(raw)
        let second = manager.parseRecurrenceString(raw)

        XCTAssertEqual(first.freq, second.freq)
        XCTAssertEqual(first.interval, second.interval)
        XCTAssertEqual(first.byDay, second.byDay)
        XCTAssertEqual(first.byMonth, second.byMonth)
        XCTAssertEqual(first.byMonthDay, second.byMonthDay)
    }

    func testParseRecurrenceStringDoesNotCollideAcrossDifferentRules() {
        let manager = RecurrenceManager(context: nil)
        let daily = manager.parseRecurrenceString("RRULE:FREQ=DAILY;INTERVAL=1")
        let weekly = manager.parseRecurrenceString("RRULE:FREQ=WEEKLY;INTERVAL=3;BYDAY=FR")

        XCTAssertNotEqual(daily.freq, weekly.freq)
        XCTAssertNotEqual(daily.interval, weekly.interval)
        XCTAssertNotEqual(daily.byDay, weekly.byDay)
    }

    func testNextOccurrenceMatchesExpectedForDailyAndWeeklyRules() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let manager = RecurrenceManager(context: context)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let person = try makePerson(context: context, name: "Rule Tester")

        let dailyStart = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 2,
            hour: 0,
            minute: 0
        ).date!
        let dailyNow = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 2,
            hour: 9,
            minute: 0
        ).date!
        let dailyDoseTime = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2001,
            month: 1,
            day: 1,
            hour: 10,
            minute: 0
        ).date!

        let dailyTherapy = try makeTherapy(
            context: context,
            medicine: medicine,
            package: package,
            person: person,
            startDate: dailyStart,
            rrule: "RRULE:FREQ=DAILY",
            doseTime: dailyDoseTime
        )

        let dailyRule = manager.parseRecurrenceString(dailyTherapy.rrule ?? "")
        let dailyNext = manager.nextOccurrence(
            rule: dailyRule,
            startDate: dailyStart,
            after: dailyNow,
            doses: dailyTherapy.doses as NSSet?
        )
        let expectedDaily = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 2,
            hour: 10,
            minute: 0
        ).date!
        XCTAssertEqual(dailyNext, expectedDaily)

        let weeklyStart = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 5,
            hour: 0,
            minute: 0
        ).date!
        let weeklyNow = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 6,
            hour: 9,
            minute: 0
        ).date!
        let weeklyDoseTime = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2001,
            month: 1,
            day: 1,
            hour: 8,
            minute: 0
        ).date!

        let weeklyTherapy = try makeTherapy(
            context: context,
            medicine: medicine,
            package: package,
            person: person,
            startDate: weeklyStart,
            rrule: "RRULE:FREQ=WEEKLY;BYDAY=WE",
            doseTime: weeklyDoseTime
        )

        let weeklyRule = manager.parseRecurrenceString(weeklyTherapy.rrule ?? "")
        let weeklyNext = manager.nextOccurrence(
            rule: weeklyRule,
            startDate: weeklyStart,
            after: weeklyNow,
            doses: weeklyTherapy.doses as NSSet?
        )
        let expectedWeekly = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 7,
            hour: 8,
            minute: 0
        ).date!
        XCTAssertEqual(weeklyNext, expectedWeekly)
    }

    private func makePerson(context: NSManagedObjectContext, name: String) throws -> Person {
        guard let entity = NSEntityDescription.entity(forEntityName: "Person", in: context) else {
            throw NSError(domain: "RecurrenceManagerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Person entity"])
        }
        let person = Person(entity: entity, insertInto: context)
        person.id = UUID()
        person.nome = name
        return person
    }

    private func makeTherapy(
        context: NSManagedObjectContext,
        medicine: Medicine,
        package: Package,
        person: Person,
        startDate: Date,
        rrule: String,
        doseTime: Date
    ) throws -> Therapy {
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package
        therapy.person = person
        therapy.start_date = startDate
        therapy.rrule = rrule

        guard let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(domain: "RecurrenceManagerTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing Dose entity"])
        }
        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.amount = NSNumber(value: 1.0)
        dose.time = doseTime
        dose.therapy = therapy
        therapy.doses = [dose]
        return therapy
    }
}
