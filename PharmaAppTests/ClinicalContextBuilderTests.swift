import XCTest
@testable import PharmaApp

final class ClinicalContextBuilderTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testBuildMonitoringTodoBeforeDoseUsesTriggerTimestampInId() throws {
        let now = makeDate(2026, 2, 18, 8, 0)
        let doseDate = makeDate(2026, 2, 18, 10, 0)
        let expectedTrigger = makeDate(2026, 2, 18, 9, 30)

        let medicineId = MedicineId(UUID())
        let therapyId = TherapyId(UUID())
        let medicine = makeMedicineSnapshot(medicineId: medicineId, therapyId: therapyId, doseDate: doseDate, relation: .beforeDose, offset: 30)

        let builder = ClinicalContextBuilder(
            recurrenceService: PureRecurrenceService(),
            calendar: calendar
        )
        let context = builder.build(for: [medicine], now: now)

        let todo = try XCTUnwrap(context.monitoring.first)
        let descriptor = try XCTUnwrap(MonitoringTodoDescriptor.parse(id: todo.id))

        XCTAssertEqual(descriptor.sourceKind, .dose)
        XCTAssertEqual(descriptor.doseRelation, .beforeDose)
        XCTAssertEqual(descriptor.doseTimestamp, doseDate)
        XCTAssertEqual(descriptor.triggerTimestamp, expectedTrigger)
        XCTAssertEqual(todo.detail, "Prima della dose (30 min prima)")
    }

    func testBuildMonitoringTodoAfterDoseUsesTriggerTimestampInId() throws {
        let now = makeDate(2026, 2, 18, 10, 10)
        let doseDate = makeDate(2026, 2, 18, 10, 0)
        let expectedTrigger = makeDate(2026, 2, 18, 10, 45)

        let medicineId = MedicineId(UUID())
        let therapyId = TherapyId(UUID())
        let medicine = makeMedicineSnapshot(medicineId: medicineId, therapyId: therapyId, doseDate: doseDate, relation: .afterDose, offset: 45)

        let builder = ClinicalContextBuilder(
            recurrenceService: PureRecurrenceService(),
            calendar: calendar
        )
        let context = builder.build(for: [medicine], now: now)

        let todo = try XCTUnwrap(context.monitoring.first)
        let descriptor = try XCTUnwrap(MonitoringTodoDescriptor.parse(id: todo.id))

        XCTAssertEqual(descriptor.sourceKind, .dose)
        XCTAssertEqual(descriptor.doseRelation, .afterDose)
        XCTAssertEqual(descriptor.doseTimestamp, doseDate)
        XCTAssertEqual(descriptor.triggerTimestamp, expectedTrigger)
        XCTAssertEqual(todo.detail, "Dopo la dose (45 min dopo)")
    }

    private func makeMedicineSnapshot(
        medicineId: MedicineId,
        therapyId: TherapyId,
        doseDate: Date,
        relation: MonitoringDoseRelation,
        offset: Int
    ) -> MedicineSnapshot {
        let therapy = TherapySnapshot(
            id: therapyId,
            externalKey: "x-coredata://therapy/\(therapyId.rawValue.uuidString)",
            medicineId: medicineId,
            packageId: PackageId(UUID()),
            packageKey: "x-coredata://package/\(UUID().uuidString)",
            startDate: calendar.date(byAdding: .day, value: -1, to: doseDate),
            rrule: "RRULE:FREQ=DAILY",
            doses: [DoseSnapshot(time: doseDate, amount: 1)],
            leftoverUnits: 10,
            manualIntakeRegistration: false,
            clinicalRules: ClinicalRules(
                monitoring: [
                    MonitoringAction(
                        kind: .bloodPressure,
                        doseRelation: relation,
                        offsetMinutes: offset,
                        requiredBeforeDose: relation == .beforeDose,
                        schedule: nil,
                        leadMinutes: offset
                    )
                ]
            ),
            personName: nil
        )

        return MedicineSnapshot(
            id: medicineId,
            externalKey: "x-coredata://medicine/\(medicineId.rawValue.uuidString)",
            name: "Test",
            requiresPrescription: false,
            inCabinet: true,
            manualIntakeRegistration: false,
            hasPackages: true,
            hasMedicinePackages: false,
            deadlineMonth: nil,
            deadlineYear: nil,
            stockUnitsWithoutTherapy: 10,
            therapies: [therapy],
            logs: []
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ).date!
    }
}
