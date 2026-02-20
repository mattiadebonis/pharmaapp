import Testing
import CoreData
@testable import PharmaApp

private final class InMemoryStockAlertStore: StockAlertStateStore {
    private var states: [UUID: StockAlertState] = [:]

    func state(for medicineId: UUID) -> StockAlertState? {
        states[medicineId]
    }

    func setState(_ state: StockAlertState, for medicineId: UUID) {
        states[medicineId] = state
    }

    func clearState(for medicineId: UUID) {
        states.removeValue(forKey: medicineId)
    }
}

@MainActor
struct NotificationPlannerTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func therapyNotificationsAreSortedAndCapped() throws {
        let context = makeContext()
        let now = makeDate(2026, 1, 26, 7, 0)
        let (medicine, package) = makeMedicine(context: context, name: "Aspirina")
        let person = makePerson(context: context, name: "Luca", surname: "Rossi")
        let doseTimes = [
            makeDate(2026, 1, 26, 8, 0),
            makeDate(2026, 1, 26, 20, 0)
        ]
        let therapy = makeTherapy(
            context: context,
            medicine: medicine,
            package: package,
            person: person,
            start: makeDate(2026, 1, 26, 0, 0),
            rrule: "RRULE:FREQ=DAILY",
            doseTimes: doseTimes
        )

        let store = InMemoryStockAlertStore()
        let planner = NotificationPlanner(
            context: context,
            calendar: calendar,
            config: NotificationScheduleConfiguration(therapyHorizonDays: 1),
            stockAlertStore: store
        )

        let items = planner.planTherapyNotifications(therapies: [therapy], now: now)
        #expect(items.count == 2)
        #expect(items[0].date < items[1].date)
        #expect(items.allSatisfy { $0.kind == .therapy })
    }

    @Test func therapyNotificationIsSkippedWhenDoseAlreadyLogged() throws {
        let context = makeContext()
        let now = makeDate(2026, 1, 26, 7, 0)
        let (medicine, package) = makeMedicine(context: context, name: "Aspirina")
        let person = makePerson(context: context, name: "Luca", surname: "Rossi")
        let therapy = makeTherapy(
            context: context,
            medicine: medicine,
            package: package,
            person: person,
            start: makeDate(2026, 1, 26, 0, 0),
            rrule: "RRULE:FREQ=DAILY",
            doseTimes: [
                makeDate(2026, 1, 26, 8, 0),
                makeDate(2026, 1, 26, 20, 0)
            ]
        )
        makeIntakeLog(
            context: context,
            medicine: medicine,
            package: package,
            therapy: therapy,
            timestamp: makeDate(2026, 1, 26, 8, 5)
        )

        let planner = NotificationPlanner(
            context: context,
            calendar: calendar,
            config: NotificationScheduleConfiguration(
                therapyHorizonDays: 1,
                therapyIntakeLogToleranceSeconds: 60 * 60
            ),
            stockAlertStore: InMemoryStockAlertStore()
        )

        let items = planner.planTherapyNotifications(therapies: [therapy], now: now)
        #expect(items.count == 1)
        #expect(items[0].date == makeDate(2026, 1, 26, 20, 0))
    }

    @Test func unassignedIntakeLogSkipsNotificationWhenSingleTherapy() throws {
        let context = makeContext()
        let now = makeDate(2026, 1, 26, 7, 0)
        let (medicine, package) = makeMedicine(context: context, name: "Aspirina")
        let person = makePerson(context: context, name: "Luca", surname: "Rossi")
        let therapy = makeTherapy(
            context: context,
            medicine: medicine,
            package: package,
            person: person,
            start: makeDate(2026, 1, 26, 0, 0),
            rrule: "RRULE:FREQ=DAILY",
            doseTimes: [makeDate(2026, 1, 26, 8, 0)]
        )
        makeIntakeLog(
            context: context,
            medicine: medicine,
            package: package,
            therapy: nil,
            timestamp: makeDate(2026, 1, 26, 8, 10)
        )

        let planner = NotificationPlanner(
            context: context,
            calendar: calendar,
            config: NotificationScheduleConfiguration(therapyHorizonDays: 1),
            stockAlertStore: InMemoryStockAlertStore()
        )

        let items = planner.planTherapyNotifications(therapies: [therapy], now: now)
        #expect(items.isEmpty)
    }

    @Test func deletedTherapyDoesNotScheduleNotifications() throws {
        let context = makeContext()
        let now = makeDate(2026, 1, 26, 7, 0)
        let (medicine, package) = makeMedicine(context: context, name: "Aspirina")
        let person = makePerson(context: context, name: "Luca", surname: "Rossi")
        let therapy = makeTherapy(
            context: context,
            medicine: medicine,
            package: package,
            person: person,
            start: makeDate(2026, 1, 26, 0, 0),
            rrule: "RRULE:FREQ=DAILY",
            doseTimes: [makeDate(2026, 1, 26, 8, 0)]
        )
        context.delete(therapy)

        let planner = NotificationPlanner(
            context: context,
            calendar: calendar,
            config: NotificationScheduleConfiguration(therapyHorizonDays: 1),
            stockAlertStore: InMemoryStockAlertStore()
        )

        let items = planner.planTherapyNotifications(therapies: [therapy], now: now)
        #expect(items.isEmpty)
    }

    @Test func stockForecastSchedulesLowAndOut() throws {
        let context = makeContext()
        let now = makeDate(2026, 1, 26, 8, 0)
        let (medicine, package) = makeMedicine(context: context, name: "Tachipirina")
        let person = makePerson(context: context, name: "Anna", surname: "Bianchi")
        _ = makeTherapy(
            context: context,
            medicine: medicine,
            package: package,
            person: person,
            start: makeDate(2026, 1, 26, 0, 0),
            rrule: "RRULE:FREQ=DAILY",
            doseTimes: [makeDate(2026, 1, 26, 9, 0)]
        )
        StockService(context: context).setUnits(10, for: package)

        let store = InMemoryStockAlertStore()
        let planner = NotificationPlanner(
            context: context,
            calendar: calendar,
            config: NotificationScheduleConfiguration(stockForecastHorizonDays: 30),
            stockAlertStore: store
        )

        let items = planner.planStockNotifications(medicines: [medicine], now: now)
        let lowItems = items.filter { $0.kind == .stockLow && $0.origin == .scheduled }
        let outItems = items.filter { $0.kind == .stockOut && $0.origin == .scheduled }
        #expect(lowItems.count == 1)
        #expect(outItems.count == 1)

        let lowDate = lowItems[0].date
        let outDate = outItems[0].date
        #expect(lowDate < outDate)
    }

    @Test func lowStockImmediateIsDebounced() throws {
        let context = makeContext()
        let now = makeDate(2026, 1, 26, 8, 0)
        let (medicine, package) = makeMedicine(context: context, name: "Zyrtec")
        StockService(context: context).setUnits(3, for: package)

        let store = InMemoryStockAlertStore()
        let planner = NotificationPlanner(
            context: context,
            calendar: calendar,
            config: NotificationScheduleConfiguration(stockAlertCooldownHours: 48),
            stockAlertStore: store
        )

        let first = planner.planStockNotifications(medicines: [medicine], now: now)
        #expect(first.contains { $0.origin == .immediate })

        let second = planner.planStockNotifications(medicines: [medicine], now: now.addingTimeInterval(3600))
        #expect(second.isEmpty)
    }

    private func makeMedicine(context: NSManagedObjectContext, name: String) -> (Medicine, Package) {
        guard let medicineEntity = NSEntityDescription.entity(forEntityName: "Medicine", in: context),
              let packageEntity = NSEntityDescription.entity(forEntityName: "Package", in: context) else {
            fatalError("Missing Medicine or Package entity in Core Data model.")
        }
        let medicine = Medicine(entity: medicineEntity, insertInto: context)
        medicine.id = UUID()
        medicine.nome = name
        medicine.principio_attivo = ""
        medicine.obbligo_ricetta = false
        medicine.custom_stock_threshold = 0
        medicine.deadline_month = 0
        medicine.deadline_year = 0
        medicine.manual_intake_registration = false
        medicine.missed_dose_preset = nil
        medicine.safety_max_per_day = 0
        medicine.safety_min_interval_hours = 0
        medicine.in_cabinet = true

        let package = Package(entity: packageEntity, insertInto: context)
        package.id = UUID()
        package.numero = 1
        package.tipologia = "compresse"
        package.valore = 0
        package.unita = ""
        package.volume = ""
        package.medicine = medicine
        medicine.addToPackages(package)

        return (medicine, package)
    }

    private func makePerson(context: NSManagedObjectContext, name: String, surname: String) -> Person {
        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context) else {
            fatalError("Missing Person entity in Core Data model.")
        }
        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = name
        person.cognome = surname
        return person
    }

    private func makeTherapy(
        context: NSManagedObjectContext,
        medicine: Medicine,
        package: Package,
        person: Person,
        start: Date,
        rrule: String,
        doseTimes: [Date]
    ) -> Therapy {
        guard let therapyEntity = NSEntityDescription.entity(forEntityName: "Therapy", in: context),
              let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            fatalError("Missing Therapy or Dose entity in Core Data model.")
        }
        let therapy = Therapy(entity: therapyEntity, insertInto: context)
        therapy.id = UUID()
        therapy.medicine = medicine
        therapy.package = package
        therapy.person = person
        therapy.start_date = start
        therapy.rrule = rrule
        therapy.manual_intake_registration = false

        var doseSet: Set<Dose> = []
        for time in doseTimes {
            let dose = Dose(entity: doseEntity, insertInto: context)
            dose.id = UUID()
            dose.time = time
            dose.therapy = therapy
            doseSet.insert(dose)
        }
        therapy.doses = doseSet
        medicine.addToTherapies(therapy)
        return therapy
    }

    private func makeIntakeLog(
        context: NSManagedObjectContext,
        medicine: Medicine,
        package: Package,
        therapy: Therapy?,
        timestamp: Date
    ) {
        guard let logEntity = NSEntityDescription.entity(forEntityName: "Log", in: context) else {
            fatalError("Missing Log entity in Core Data model.")
        }
        let log = Log(entity: logEntity, insertInto: context)
        log.id = UUID()
        log.type = "intake"
        log.timestamp = timestamp
        log.medicine = medicine
        log.package = package
        log.therapy = therapy
        medicine.addToLogs(log)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }

    private func makeContext() -> NSManagedObjectContext {
        let bundles = [
            Bundle(for: AppDelegate.self),
            Bundle.main,
            Bundle(for: Medicine.self)
        ]
        let model = NSManagedObjectModel.mergedModel(from: bundles)
        guard let model, model.entitiesByName["Medicine"] != nil else {
            fatalError("Missing Core Data model or Medicine entity in test bundle.")
        }
        let container = NSPersistentContainer(name: "PharmaApp", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load in-memory store: \\(error)")
            }
        }
        return container.viewContext
    }
}
