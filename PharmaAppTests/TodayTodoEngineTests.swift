import XCTest
import CoreData
@testable import PharmaApp

final class TodayTodoEngineTests: XCTestCase {
    func testCompletionKeyUsesItemIDForMonitoringAndMissedDose() {
        let monitoring = TodayTodoItem(
            id: "monitoring|bp|systolic|123",
            title: "Monitoraggio",
            detail: nil,
            category: .monitoring,
            medicineId: nil
        )
        XCTAssertEqual(TodayTodoEngine.completionKey(for: monitoring), monitoring.id)

        let missed = TodayTodoItem(
            id: "missed|dose|123",
            title: "Dose mancata",
            detail: nil,
            category: .missedDose,
            medicineId: nil
        )
        XCTAssertEqual(TodayTodoEngine.completionKey(for: missed), missed.id)
    }

    func testSyncTokenChangesWhenDetailChanges() {
        let base = TodayTodoItem(
            id: "therapy|a",
            title: "Terapia",
            detail: "08:00",
            category: .therapy,
            medicineId: nil
        )
        let token1 = TodayTodoEngine.syncToken(for: [base])

        let updated = TodayTodoItem(
            id: "therapy|a",
            title: "Terapia",
            detail: "09:00",
            category: .therapy,
            medicineId: nil
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
            medicineId: nil
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

    func testTodayEngineUnlocksBuyWhenPrescriptionReceived() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.obbligo_ricetta = true
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        try context.save()

        let recManager = RecurrenceManager(context: context)
        XCTAssertTrue(TodayTodoEngine.needsPrescriptionBeforePurchase(medicine, option: nil, recurrenceManager: recManager))

        let useCase = RecordPrescriptionReceivedUseCase(
            eventStore: CoreDataEventStore(context: context),
            clock: SystemClock()
        )
        let request = RecordPrescriptionReceivedRequest(
            operationId: UUID(),
            medicineId: MedicineId(medicine.id),
            packageId: PackageId(package.id)
        )
        _ = try useCase.execute(request)

        XCTAssertFalse(TodayTodoEngine.needsPrescriptionBeforePurchase(medicine, option: nil, recurrenceManager: recManager))
    }

    func testTherapyWithoutDosesIsNotShownToday() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "NoDoseMed"
        medicine.in_cabinet = true

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context) else {
            XCTFail("Missing Person entity")
            return
        }
        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Test"

        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.rrule = "FREQ=DAILY"
        therapy.start_date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        therapy.package = package
        therapy.person = person
        therapy.doses = []

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 2,
            day: 3,
            hour: 10,
            minute: 0
        ).date!
        let recurrenceManager = RecurrenceManager(context: context)
        let clinicalContext = ClinicalContextBuilder(context: context).build(for: [medicine])
        let state = TodayTodoEngine.buildState(
            medicines: [medicine],
            logs: [],
            todos: [],
            option: nil,
            completedTodoIDs: [],
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext,
            now: now,
            calendar: calendar
        )

        let therapyItems = state.computedTodos.filter { $0.category == .therapy && $0.medicineId == MedicineId(medicine.id) }
        XCTAssertEqual(therapyItems.count, 0, "Therapy without doses should not be shown for today")
    }

    func testTherapyShowsEvenIfInCabinetFlagIsFalse() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "LegacyMed"
        medicine.in_cabinet = false

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context),
              let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            XCTFail("Missing CoreData entities")
            return
        }

        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Test"

        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.rrule = "FREQ=DAILY"
        therapy.start_date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        therapy.package = package
        therapy.person = person

        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        dose.therapy = therapy
        therapy.doses = [dose]

        let recurrenceManager = RecurrenceManager(context: context)
        let clinicalContext = ClinicalContextBuilder(context: context).build(for: [medicine])
        let state = TodayTodoEngine.buildState(
            medicines: [medicine],
            logs: [],
            todos: [],
            option: nil,
            completedTodoIDs: [],
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext
        )

        let therapyItems = state.computedTodos.filter { $0.category == .therapy && $0.medicineId == MedicineId(medicine.id) }
        XCTAssertEqual(therapyItems.count, 1, "Legacy medicines with therapies should still show today")
    }

    func testTherapyItemRemainsWhenSomeDosesStillPendingToday() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "DailyMed"
        medicine.in_cabinet = true

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context),
              let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context),
              let logEntity = NSEntityDescription.entity(forEntityName: "Log", in: context),
              let todoEntity = NSEntityDescription.entity(forEntityName: "Todo", in: context) else {
            XCTFail("Missing CoreData entities")
            return
        }

        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Test"

        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.rrule = "FREQ=DAILY"
        therapy.start_date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        therapy.package = package
        therapy.person = person

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 2,
            day: 3,
            hour: 19,
            minute: 0
        ).date!

        let morningDose = Dose(entity: doseEntity, insertInto: context)
        morningDose.id = UUID()
        morningDose.time = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        morningDose.therapy = therapy

        let eveningDose = Dose(entity: doseEntity, insertInto: context)
        eveningDose.id = UUID()
        eveningDose.time = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        eveningDose.therapy = therapy

        therapy.doses = [morningDose, eveningDose]

        let intakeLog = Log(entity: logEntity, insertInto: context)
        intakeLog.id = UUID()
        intakeLog.type = "intake"
        intakeLog.timestamp = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        intakeLog.medicine = medicine
        intakeLog.therapy = therapy
        intakeLog.package = package

        let todo = Todo(entity: todoEntity, insertInto: context)
        todo.id = UUID()
        todo.source_id = "therapy|daily"
        todo.title = medicine.nome
        todo.detail = "08:00"
        todo.category = TodayTodoItem.Category.therapy.rawValue
        todo.created_at = Date()
        todo.updated_at = Date()
        todo.medicine = medicine

        let recurrenceManager = RecurrenceManager(context: context)
        let clinicalContext = ClinicalContextBuilder(context: context).build(for: [medicine])
        let state = TodayTodoEngine.buildState(
            medicines: [medicine],
            logs: [],
            todos: [todo],
            option: nil,
            completedTodoIDs: [],
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext,
            now: now,
            calendar: calendar
        )

        let therapyItems = state.pendingItems.filter { $0.category == .therapy }
        XCTAssertEqual(therapyItems.count, 1, "Therapy should remain visible when there are still doses pending today")
    }

    func testTherapyItemHiddenWhenAllDosesLoggedToday() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "FullLoggedMed"
        medicine.in_cabinet = true

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context),
              let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context),
              let logEntity = NSEntityDescription.entity(forEntityName: "Log", in: context),
              let todoEntity = NSEntityDescription.entity(forEntityName: "Todo", in: context) else {
            XCTFail("Missing CoreData entities")
            return
        }

        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Test"

        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.rrule = "FREQ=DAILY"
        therapy.start_date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        therapy.package = package
        therapy.person = person

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 2,
            day: 3,
            hour: 22,
            minute: 0
        ).date!

        let morningDose = Dose(entity: doseEntity, insertInto: context)
        morningDose.id = UUID()
        morningDose.time = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        morningDose.therapy = therapy

        let eveningDose = Dose(entity: doseEntity, insertInto: context)
        eveningDose.id = UUID()
        eveningDose.time = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        eveningDose.therapy = therapy

        therapy.doses = [morningDose, eveningDose]

        let intakeLog1 = Log(entity: logEntity, insertInto: context)
        intakeLog1.id = UUID()
        intakeLog1.type = "intake"
        intakeLog1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        intakeLog1.medicine = medicine
        intakeLog1.therapy = therapy
        intakeLog1.package = package

        let intakeLog2 = Log(entity: logEntity, insertInto: context)
        intakeLog2.id = UUID()
        intakeLog2.type = "intake"
        intakeLog2.timestamp = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now) ?? now
        intakeLog2.medicine = medicine
        intakeLog2.therapy = therapy
        intakeLog2.package = package

        let todo = Todo(entity: todoEntity, insertInto: context)
        todo.id = UUID()
        todo.source_id = "therapy|daily"
        todo.title = medicine.nome
        todo.detail = "08:00"
        todo.category = TodayTodoItem.Category.therapy.rawValue
        todo.created_at = Date()
        todo.updated_at = Date()
        todo.medicine = medicine

        let recurrenceManager = RecurrenceManager(context: context)
        let clinicalContext = ClinicalContextBuilder(context: context).build(for: [medicine])
        let state = TodayTodoEngine.buildState(
            medicines: [medicine],
            logs: [],
            todos: [todo],
            option: nil,
            completedTodoIDs: [],
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext,
            now: now,
            calendar: calendar
        )

        let therapyItems = state.pendingItems.filter { $0.category == .therapy }
        XCTAssertEqual(therapyItems.count, 0, "Therapy should be hidden when all doses are logged today")
    }

    func testCompletedTodoIDsDoesNotHideTherapy() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "CompletedIgnoreMed"
        medicine.in_cabinet = true

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context),
              let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context),
              let todoEntity = NSEntityDescription.entity(forEntityName: "Todo", in: context) else {
            XCTFail("Missing CoreData entities")
            return
        }

        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Test"

        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.rrule = "FREQ=DAILY"
        therapy.start_date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        therapy.package = package
        therapy.person = person

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 2,
            day: 3,
            hour: 10,
            minute: 0
        ).date!

        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.time = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        dose.therapy = therapy
        therapy.doses = [dose]

        let todo = Todo(entity: todoEntity, insertInto: context)
        todo.id = UUID()
        todo.source_id = "therapy|daily"
        todo.title = medicine.nome
        todo.detail = "09:00"
        todo.category = TodayTodoItem.Category.therapy.rawValue
        todo.created_at = Date()
        todo.updated_at = Date()
        todo.medicine = medicine

        let recurrenceManager = RecurrenceManager(context: context)
        let clinicalContext = ClinicalContextBuilder(context: context).build(for: [medicine])
        let completed = Set([TodayTodoEngine.completionKey(for: TodayTodoItem(todo: todo)!)])
        let state = TodayTodoEngine.buildState(
            medicines: [medicine],
            logs: [],
            todos: [todo],
            option: nil,
            completedTodoIDs: completed,
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext,
            now: now,
            calendar: calendar
        )

        let therapyItems = state.pendingItems.filter { $0.category == .therapy }
        XCTAssertEqual(therapyItems.count, 1, "Therapy should not be hidden by completedTodoIDs")
    }
}
