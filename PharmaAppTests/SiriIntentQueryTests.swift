import XCTest
import CoreData
@testable import PharmaApp

final class SiriIntentQueryTests: XCTestCase {
    func testCosaDevoPrendereAdessoRestituisceEventoCorretto() throws {
        let (context, medicine, package) = try makeMedicineFixture(name: "Cardioaspirina")
        _ = try attachDailyTherapy(
            to: medicine,
            package: package,
            context: context,
            hour: Calendar.current.component(.hour, from: Date()),
            minute: min(59, Calendar.current.component(.minute, from: Date()) + 1)
        )
        try context.save()

        let facade = SiriIntentFacade(
            context: context,
            operationIdProvider: InMemoryOperationIdProvider(),
            routeStore: InMemoryPendingRouteStore()
        )

        let next = facade.nextDoseNow()

        XCTAssertNotNil(next)
        XCTAssertEqual(next?.medicine.name, medicine.nome)
    }

    func testHoPresoTuttoPerOggiNoPoiSi() throws {
        let (context, medicine, package) = try makeMedicineFixture(name: "Bisoprololo")
        let therapy = try attachDailyTherapy(
            to: medicine,
            package: package,
            context: context,
            hour: 9,
            minute: 0
        )
        try context.save()

        let facade = SiriIntentFacade(
            context: context,
            operationIdProvider: InMemoryOperationIdProvider(),
            routeStore: InMemoryPendingRouteStore()
        )

        let before = facade.doneTodayStatus()
        XCTAssertFalse(before.isDone)
        XCTAssertTrue(before.missingMedicines.contains(medicine.nome))

        let stockService = StockService(context: context)
        _ = stockService.createLog(
            type: "intake",
            medicine: medicine,
            package: package,
            therapy: therapy,
            operationId: UUID()
        )

        let after = facade.doneTodayStatus()
        XCTAssertTrue(after.isDone)
    }

    func testCosaDevoComprareRestituisceMaxTrePiuConteggioExtra() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext

        for idx in 0..<4 {
            let medicine = try TestCoreDataFactory.makeMedicine(context: context)
            medicine.nome = "Med \(idx)"
            medicine.in_cabinet = true
            let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 10)
            _ = try attachDailyTherapy(
                to: medicine,
                package: package,
                context: context,
                hour: 8 + idx,
                minute: 0
            )
        }
        try context.save()

        let facade = SiriIntentFacade(
            context: context,
            operationIdProvider: InMemoryOperationIdProvider(),
            routeStore: InMemoryPendingRouteStore()
        )

        let summary = facade.purchaseSummary(maxItems: 3)

        XCTAssertGreaterThanOrEqual(summary.totalCount, 4)
        XCTAssertEqual(summary.items.count, 3)
        XCTAssertEqual(summary.remainingCount, summary.totalCount - 3)
    }

    func testNextIntakeDateMantieneLaDoseSaltataFincheNonC_eUnaNuovaAssunzione() throws {
        let calendar = makeCalendar()
        let (context, medicine, package) = try makeMedicineFixture(name: "Metformina")
        let therapy = try attachDailyTherapy(
            to: medicine,
            package: package,
            context: context,
            doseTimes: [
                makeDate(2026, 2, 28, 8, 0, calendar: calendar),
                makeDate(2026, 2, 28, 20, 0, calendar: calendar)
            ],
            startDate: makeDate(2026, 2, 27, 8, 0, calendar: calendar)
        )
        try context.save()

        let recurrenceManager = RecurrenceManager(context: context)
        let beforeIntake = makeDate(2026, 2, 28, 12, 0, calendar: calendar)
        XCTAssertEqual(
            medicine.nextIntakeDate(from: beforeIntake, recurrenceManager: recurrenceManager, calendar: calendar),
            makeDate(2026, 2, 28, 8, 0, calendar: calendar)
        )

        _ = try makeIntakeLog(
            context: context,
            medicine: medicine,
            package: package,
            therapy: therapy,
            timestamp: makeDate(2026, 2, 28, 15, 0, calendar: calendar)
        )
        try context.save()

        let afterIntake = makeDate(2026, 2, 28, 15, 30, calendar: calendar)
        XCTAssertEqual(
            medicine.nextIntakeDate(from: afterIntake, recurrenceManager: recurrenceManager, calendar: calendar),
            makeDate(2026, 2, 28, 20, 0, calendar: calendar)
        )
    }

    func testProviderNextUpcomingDoseDateMantieneLaDoseSaltataFincheNonC_eUnaNuovaAssunzione() throws {
        let calendar = makeCalendar()
        let (context, medicine, package) = try makeMedicineFixture(name: "Bisoprololo")
        let therapy = try attachDailyTherapy(
            to: medicine,
            package: package,
            context: context,
            doseTimes: [
                makeDate(2026, 2, 28, 8, 0, calendar: calendar),
                makeDate(2026, 2, 28, 20, 0, calendar: calendar)
            ],
            startDate: makeDate(2026, 2, 27, 8, 0, calendar: calendar)
        )
        try context.save()

        let provider = CoreDataTherapyPlanProvider(context: context, calendar: calendar)
        let beforeIntake = makeDate(2026, 2, 28, 12, 0, calendar: calendar)
        XCTAssertEqual(
            provider.nextUpcomingDoseDate(for: medicine, now: beforeIntake),
            makeDate(2026, 2, 28, 8, 0, calendar: calendar)
        )

        _ = try makeIntakeLog(
            context: context,
            medicine: medicine,
            package: package,
            therapy: therapy,
            timestamp: makeDate(2026, 2, 28, 15, 0, calendar: calendar)
        )
        try context.save()

        let afterIntake = makeDate(2026, 2, 28, 15, 30, calendar: calendar)
        XCTAssertEqual(
            provider.nextUpcomingDoseDate(for: medicine, now: afterIntake),
            makeDate(2026, 2, 28, 20, 0, calendar: calendar)
        )
    }

    private func makeMedicineFixture(name: String) throws -> (NSManagedObjectContext, Medicine, Package) {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = name
        medicine.in_cabinet = true
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 30)
        return (context, medicine, package)
    }

    private func attachDailyTherapy(
        to medicine: Medicine,
        package: Package,
        context: NSManagedObjectContext,
        hour: Int,
        minute: Int
    ) throws -> Therapy {
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package
        therapy.rrule = "RRULE:FREQ=DAILY;INTERVAL=1"
        therapy.start_date = Calendar.current.startOfDay(for: Date())

        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context) else {
            throw NSError(domain: "SiriIntentQueryTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Person entity missing"])
        }
        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Persona Test"
        therapy.person = person

        guard let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(domain: "SiriIntentQueryTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Dose entity missing"])
        }
        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.amount = NSNumber(value: 1)
        dose.time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        dose.therapy = therapy
        therapy.doses = [dose]

        return therapy
    }

    private func attachDailyTherapy(
        to medicine: Medicine,
        package: Package,
        context: NSManagedObjectContext,
        doseTimes: [Date],
        startDate: Date
    ) throws -> Therapy {
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package
        therapy.rrule = "RRULE:FREQ=DAILY;INTERVAL=1"
        therapy.start_date = startDate

        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context) else {
            throw NSError(domain: "SiriIntentQueryTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Person entity missing"])
        }
        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Persona Test"
        therapy.person = person

        guard let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(domain: "SiriIntentQueryTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Dose entity missing"])
        }

        var doses: Set<Dose> = []
        for time in doseTimes {
            let dose = Dose(entity: doseEntity, insertInto: context)
            dose.id = UUID()
            dose.amount = NSNumber(value: 1)
            dose.time = time
            dose.therapy = therapy
            doses.insert(dose)
        }
        therapy.doses = doses

        return therapy
    }

    private func makeIntakeLog(
        context: NSManagedObjectContext,
        medicine: Medicine,
        package: Package,
        therapy: Therapy,
        timestamp: Date
    ) throws -> Log {
        guard let logEntity = NSEntityDescription.entity(forEntityName: "Log", in: context) else {
            throw NSError(domain: "SiriIntentQueryTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Log entity missing"])
        }

        let log = Log(entity: logEntity, insertInto: context)
        log.id = UUID()
        log.type = "intake"
        log.timestamp = timestamp
        log.medicine = medicine
        log.package = package
        log.therapy = therapy
        medicine.addToLogs(log)
        return log
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "it_IT")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? Date()
    }
}

private final class InMemoryOperationIdProvider: OperationIdProviding {
    private var storage: [OperationKey: UUID] = [:]

    func operationId(for key: OperationKey, ttl: TimeInterval) -> UUID {
        if let existing = storage[key] {
            return existing
        }
        let id = UUID()
        storage[key] = id
        return id
    }

    func clear(_ key: OperationKey) {
        storage.removeValue(forKey: key)
    }

    func newOperationId() -> UUID {
        UUID()
    }
}

private final class InMemoryPendingRouteStore: PendingAppRouteStoring {
    private var route: AppRoute?

    func save(route: AppRoute) {
        self.route = route
    }

    func loadRoute() -> AppRoute? {
        route
    }

    func clearRoute() {
        route = nil
    }

    func consumeRoute() -> AppRoute? {
        let value = route
        route = nil
        return value
    }
}
