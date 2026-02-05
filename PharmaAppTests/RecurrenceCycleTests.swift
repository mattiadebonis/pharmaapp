import XCTest
import CoreData
@testable import PharmaApp

final class RecurrenceCycleTests: XCTestCase {
    func testParseCycleFrequency() {
        let parser = TherapyDescriptionParser(persons: [], defaultPerson: nil)
        let frequency = parser.parseFrequencyOnly("prendi per 7 giorni, poi 21 giorni di pausa")

        switch frequency {
        case .cycle(let onDays, let offDays):
            XCTAssertEqual(onDays, 7)
            XCTAssertEqual(offDays, 21)
        default:
            XCTFail("Expected cycle frequency")
        }
    }

    func testAllowedEventsForCycle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2024,
            month: 1,
            day: 1
        ).date!

        var rule = RecurrenceRule(freq: "DAILY")
        rule.cycleOnDays = 7
        rule.cycleOffDays = 21

        let manager = RecurrenceManager(context: nil)
        func allowed(_ offset: Int) -> Int {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return manager.allowedEvents(on: day, rule: rule, startDate: start, dosesPerDay: 1, calendar: calendar)
        }

        XCTAssertEqual(allowed(0), 1)
        XCTAssertEqual(allowed(6), 1)
        XCTAssertEqual(allowed(7), 0)
        XCTAssertEqual(allowed(27), 0)
        XCTAssertEqual(allowed(28), 1)
    }

    func testRRULECycleRoundTrip() {
        let manager = RecurrenceManager(context: nil)
        var rule = RecurrenceRule(freq: "DAILY")
        rule.cycleOnDays = 7
        rule.cycleOffDays = 21

        let rrule = manager.buildRecurrenceString(from: rule)
        XCTAssertTrue(rrule.contains("X-PHARMAPP-ON=7"))
        XCTAssertTrue(rrule.contains("X-PHARMAPP-OFF=21"))

        let parsed = manager.parseRecurrenceString(rrule)
        XCTAssertEqual(parsed.cycleOnDays, 7)
        XCTAssertEqual(parsed.cycleOffDays, 21)
    }

    func testDailyConsumptionForCycle() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package

        if let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context) {
            let person = Person(entity: personEntity, insertInto: context)
            person.id = UUID()
            person.nome = "Test"
            person.cognome = nil
            therapy.person = person
        }

        let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context)!
        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.amount = NSNumber(value: 2.0)
        dose.time = Date()
        dose.therapy = therapy

        var rule = RecurrenceRule(freq: "DAILY")
        rule.cycleOnDays = 7
        rule.cycleOffDays = 21
        let rrule = RecurrenceManager(context: context).buildRecurrenceString(from: rule)
        therapy.rrule = rrule

        let daily = therapy.stimaConsumoGiornaliero(recurrenceManager: RecurrenceManager(context: context))
        XCTAssertEqual(daily, 0.5, accuracy: 0.0001)
    }
}
