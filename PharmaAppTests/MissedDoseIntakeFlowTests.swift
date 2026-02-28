import XCTest
import CoreData
@testable import PharmaApp

final class MissedDoseIntakeFlowTests: XCTestCase {
    func testCustomMissedDoseKeepsNextScheduledDose() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let actionService = MedicineActionService(context: context)
        let now = makeDate(2026, 2, 11, 11, 0)

        guard let candidate = actionService.missedDoseCandidate(
            for: fixture.medicine,
            package: fixture.package,
            now: now
        ) else {
            XCTFail("Expected missed dose candidate")
            return
        }

        let takenAt = makeDate(2026, 2, 11, 11, 0)
        let log = actionService.recordMissedDoseIntake(
            candidate: candidate,
            takenAt: takenAt,
            nextAction: .keepSchedule,
            operationId: UUID()
        )

        XCTAssertNotNil(log)
        XCTAssertEqual(log?.scheduled_due_at, makeDate(2026, 2, 11, 8, 0))

        let next = fixture.medicine.nextIntakeDate(
            for: fixture.therapy,
            from: makeDate(2026, 2, 11, 11, 1),
            recurrenceManager: RecurrenceManager(context: context),
            calendar: calendar
        )
        XCTAssertEqual(next, makeDate(2026, 2, 11, 20, 0))
    }

    func testCustomMissedDoseCanPostponeNextDose() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let actionService = MedicineActionService(context: context)
        let now = makeDate(2026, 2, 11, 11, 0)

        guard let candidate = actionService.missedDoseCandidate(
            for: fixture.medicine,
            package: fixture.package,
            now: now
        ) else {
            XCTFail("Expected missed dose candidate")
            return
        }

        let log = actionService.recordMissedDoseIntake(
            candidate: candidate,
            takenAt: now,
            nextAction: .postponeByStandardInterval,
            operationId: UUID()
        )

        XCTAssertNotNil(log)

        let next = fixture.medicine.nextIntakeDate(
            for: fixture.therapy,
            from: makeDate(2026, 2, 11, 11, 1),
            recurrenceManager: RecurrenceManager(context: context),
            calendar: calendar
        )
        XCTAssertEqual(next, makeDate(2026, 2, 11, 23, 0))
    }

    func testPostponedNextDoseSkipsInterveningOccurrences() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let actionService = MedicineActionService(context: context)
        let takenAt = makeDate(2026, 2, 11, 23, 0)

        guard let candidate = actionService.missedDoseCandidate(
            for: fixture.medicine,
            package: fixture.package,
            now: takenAt
        ) else {
            XCTFail("Expected missed dose candidate")
            return
        }

        let log = actionService.recordMissedDoseIntake(
            candidate: candidate,
            takenAt: takenAt,
            nextAction: .postponeByStandardInterval,
            operationId: UUID()
        )

        XCTAssertNotNil(log)

        let next = fixture.medicine.nextIntakeDate(
            for: fixture.therapy,
            from: makeDate(2026, 2, 11, 23, 1),
            recurrenceManager: RecurrenceManager(context: context),
            calendar: calendar
        )
        XCTAssertEqual(next, makeDate(2026, 2, 12, 11, 0))
    }

    private var calendar: Calendar {
        Calendar(identifier: .gregorian)
    }

    private func makeFixture() throws -> (context: NSManagedObjectContext, medicine: Medicine, package: Package, therapy: Therapy) {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Terapia test"
        medicine.manual_intake_registration = true

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 30)

        let personEntity = try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Person", in: context))
        let doseEntity = try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Dose", in: context))

        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Mario"
        person.cognome = "Rossi"

        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package
        therapy.person = person
        therapy.start_date = makeDate(2026, 2, 11, 0, 0)
        therapy.rrule = "RRULE:FREQ=DAILY"
        therapy.manual_intake_registration = true

        let morningDose = Dose(entity: doseEntity, insertInto: context)
        morningDose.id = UUID()
        morningDose.time = makeDate(2026, 2, 11, 8, 0)
        morningDose.amount = NSNumber(value: 1)
        morningDose.therapy = therapy

        let eveningDose = Dose(entity: doseEntity, insertInto: context)
        eveningDose.id = UUID()
        eveningDose.time = makeDate(2026, 2, 11, 20, 0)
        eveningDose.amount = NSNumber(value: 1)
        eveningDose.therapy = therapy

        therapy.doses = [morningDose, eveningDose]
        try context.save()

        let stockService = StockService(context: context)
        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: UUID()
        )

        return (context, medicine, package, therapy)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return components.date ?? Date()
    }
}
