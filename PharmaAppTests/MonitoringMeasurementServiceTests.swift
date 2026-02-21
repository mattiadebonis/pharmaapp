import XCTest
import CoreData
@testable import PharmaApp

final class MonitoringMeasurementServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var medicine: Medicine!
    private var service: MonitoringMeasurementService!

    override func setUpWithError() throws {
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
        medicine = try TestCoreDataFactory.makeMedicine(context: context)
        try context.save()
        service = MonitoringMeasurementService(context: context)
    }

    override func tearDownWithError() throws {
        service = nil
        medicine = nil
        context = nil
        container = nil
    }

    func testSaveUpdateFetchAndDeleteMeasurementByTodoSourceID() throws {
        let todoSourceID = "monitoring|dose|bloodPressure|beforeDose|therapy-key|100|90"
        let first = try service.saveOrUpdate(
            MonitoringMeasurementPayload(
                todoSourceID: todoSourceID,
                kind: .bloodPressure,
                doseRelation: .beforeDose,
                measuredAt: Date(timeIntervalSince1970: 1000),
                scheduledAt: Date(timeIntervalSince1970: 900),
                valuePrimary: 130,
                valueSecondary: 80,
                unit: "mmHg",
                medicine: medicine,
                therapy: nil
            )
        )

        XCTAssertEqual(first.todo_source_id, todoSourceID)
        XCTAssertEqual(first.kind, MonitoringKind.bloodPressure.rawValue)
        XCTAssertEqual(first.dose_relation, MonitoringDoseRelation.beforeDose.rawValue)
        XCTAssertEqual(first.primaryValue, 130)
        XCTAssertEqual(first.secondaryValue, 80)

        let updated = try service.saveOrUpdate(
            MonitoringMeasurementPayload(
                todoSourceID: todoSourceID,
                kind: .bloodPressure,
                doseRelation: .beforeDose,
                measuredAt: Date(timeIntervalSince1970: 1100),
                scheduledAt: Date(timeIntervalSince1970: 900),
                valuePrimary: 125,
                valueSecondary: 78,
                unit: "mmHg",
                medicine: medicine,
                therapy: nil
            )
        )

        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.primaryValue, 125)
        XCTAssertEqual(updated.secondaryValue, 78)

        let fetched = try service.fetchByTodoSourceID(todoSourceID)
        XCTAssertEqual(fetched?.id, first.id)
        XCTAssertEqual(fetched?.primaryValue, 125)
        XCTAssertEqual(fetched?.secondaryValue, 78)

        XCTAssertTrue(try service.delete(todoSourceID: todoSourceID))
        XCTAssertNil(try service.fetchByTodoSourceID(todoSourceID))
    }

    func testFetchDailyReturnsAllMeasurementsForDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = DateComponents(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 2,
            day: 18,
            hour: 12,
            minute: 0
        ).date!
        let sameDayLater = dayStart.addingTimeInterval(3600)
        let nextDay = dayStart.addingTimeInterval(24 * 3600)

        _ = try service.saveOrUpdate(
            MonitoringMeasurementPayload(
                todoSourceID: "m1",
                kind: .temperature,
                doseRelation: .afterDose,
                measuredAt: dayStart,
                scheduledAt: dayStart,
                valuePrimary: 37.2,
                valueSecondary: nil,
                unit: "°C",
                medicine: medicine,
                therapy: nil
            )
        )
        _ = try service.saveOrUpdate(
            MonitoringMeasurementPayload(
                todoSourceID: "m2",
                kind: .heartRate,
                doseRelation: .afterDose,
                measuredAt: sameDayLater,
                scheduledAt: sameDayLater,
                valuePrimary: 75,
                valueSecondary: nil,
                unit: "bpm",
                medicine: medicine,
                therapy: nil
            )
        )
        _ = try service.saveOrUpdate(
            MonitoringMeasurementPayload(
                todoSourceID: "m3",
                kind: .bloodGlucose,
                doseRelation: .beforeDose,
                measuredAt: nextDay,
                scheduledAt: nextDay,
                valuePrimary: 105,
                valueSecondary: nil,
                unit: "mg/dL",
                medicine: medicine,
                therapy: nil
            )
        )

        let list = try service.fetchDaily(on: dayStart, calendar: calendar)
        XCTAssertEqual(Set(list.map { $0.todo_source_id }), Set(["m1", "m2"]))
    }
}
