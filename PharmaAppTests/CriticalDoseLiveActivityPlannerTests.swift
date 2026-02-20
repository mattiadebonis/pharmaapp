import Foundation
import CoreData
import Testing
@testable import PharmaApp

private final class PlannerSnoozeStoreFake: CriticalDoseSnoozeStoreProtocol {
    var snoozedKeys: Set<String> = []

    func isSnoozed(therapyId: UUID, scheduledAt: Date, now: Date) -> Bool {
        snoozedKeys.contains(makeKey(therapyId: therapyId, scheduledAt: scheduledAt))
    }

    @discardableResult
    func snooze(therapyId: UUID, scheduledAt: Date, now: Date, duration: TimeInterval) -> Date {
        let key = makeKey(therapyId: therapyId, scheduledAt: scheduledAt)
        snoozedKeys.insert(key)
        return now.addingTimeInterval(duration)
    }

    func clear(therapyId: UUID, scheduledAt: Date) {
        snoozedKeys.remove(makeKey(therapyId: therapyId, scheduledAt: scheduledAt))
    }

    func nextExpiry(after now: Date) -> Date? { nil }

    private func makeKey(therapyId: UUID, scheduledAt: Date) -> String {
        let bucket = Int(scheduledAt.timeIntervalSince1970 / 60)
        return "\(therapyId.uuidString)|\(bucket)"
    }
}

@MainActor
struct CriticalDoseLiveActivityPlannerTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func plannerUsesWindowAndBuildsAggregateSubtitle() throws {
        let context = try makeContext()
        let now = makeDate(2026, 2, 11, 10, 0)

        _ = try makeTherapy(
            context: context,
            medicineName: "CardioA",
            doseAt: makeDate(2026, 2, 11, 9, 40)
        )
        _ = try makeTherapy(
            context: context,
            medicineName: "CardioB",
            doseAt: makeDate(2026, 2, 11, 10, 9)
        )
        _ = try makeTherapy(
            context: context,
            medicineName: "CardioC",
            doseAt: makeDate(2026, 2, 11, 11, 10)
        )

        let planner = CriticalDoseLiveActivityPlanner(context: context)
        let plan = planner.makePlan(now: now)

        #expect(plan.aggregate != nil)
        #expect(plan.aggregate?.primary.medicineName == "CardioA")
        #expect(plan.aggregate?.additionalCount == 1)
        #expect(plan.aggregate?.subtitleDisplay.contains("+1") == true)
    }

    @Test func plannerTieBreaksByMedicineNameOnSameTime() throws {
        let context = try makeContext()
        let now = makeDate(2026, 2, 11, 10, 0)
        let sameTime = makeDate(2026, 2, 11, 10, 10)

        _ = try makeTherapy(context: context, medicineName: "Zeta", doseAt: sameTime)
        _ = try makeTherapy(context: context, medicineName: "Alfa", doseAt: sameTime)

        let planner = CriticalDoseLiveActivityPlanner(context: context)
        let plan = planner.makePlan(now: now)

        #expect(plan.aggregate?.primary.medicineName == "Alfa")
    }

    @Test func plannerSkipsSnoozedPrimaryAndSelectsNext() throws {
        let context = try makeContext()
        let now = makeDate(2026, 2, 11, 10, 10)

        let first = try makeTherapy(
            context: context,
            medicineName: "Prima",
            doseAt: makeDate(2026, 2, 11, 10, 10)
        )
        _ = try makeTherapy(
            context: context,
            medicineName: "Seconda",
            doseAt: makeDate(2026, 2, 11, 10, 20)
        )

        let snoozeStore = PlannerSnoozeStoreFake()
        let key = "\(first.id.uuidString)|\(Int(makeDate(2026, 2, 11, 10, 10).timeIntervalSince1970 / 60))"
        snoozeStore.snoozedKeys.insert(key)

        let planner = CriticalDoseLiveActivityPlanner(context: context, snoozeStore: snoozeStore)
        let plan = planner.makePlan(now: now)

        #expect(plan.aggregate?.primary.medicineName == "Seconda")
    }

    @Test func plannerSkipsAlreadyTakenDoseAndSelectsNext() throws {
        let context = try makeContext()
        let now = makeDate(2026, 2, 11, 10, 10)

        let first = try makeTherapy(
            context: context,
            medicineName: "Prima",
            doseAt: makeDate(2026, 2, 11, 10, 10)
        )
        _ = try makeTherapy(
            context: context,
            medicineName: "Seconda",
            doseAt: makeDate(2026, 2, 11, 10, 20)
        )

        _ = try makeIntakeLog(
            context: context,
            therapy: first,
            timestamp: makeDate(2026, 2, 11, 10, 8)
        )

        let planner = CriticalDoseLiveActivityPlanner(context: context)
        let plan = planner.makePlan(now: now)

        #expect(plan.aggregate?.primary.medicineName == "Seconda")
    }

    @Test func plannerShowsDoseOnlyWithinTenMinutesLeadTime() throws {
        let context = try makeContext()
        let now = makeDate(2026, 2, 11, 10, 0)

        _ = try makeTherapy(
            context: context,
            medicineName: "CardioA",
            doseAt: makeDate(2026, 2, 11, 10, 11)
        )

        let planner = CriticalDoseLiveActivityPlanner(context: context)
        let plan = planner.makePlan(now: now)

        #expect(plan.aggregate == nil)
        #expect(plan.nextRefreshAt == makeDate(2026, 2, 11, 10, 1))
    }

    private func makeContext() throws -> NSManagedObjectContext {
        try TestCoreDataFactory.makeContainer().viewContext
    }

    private func makeTherapy(
        context: NSManagedObjectContext,
        medicineName: String,
        doseAt: Date
    ) throws -> Therapy {
        guard let medicineEntity = NSEntityDescription.entity(forEntityName: "Medicine", in: context),
              let packageEntity = NSEntityDescription.entity(forEntityName: "Package", in: context),
              let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context),
              let therapyEntity = NSEntityDescription.entity(forEntityName: "Therapy", in: context),
              let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(domain: "CriticalDosePlannerTests", code: 1)
        }

        let medicine = Medicine(entity: medicineEntity, insertInto: context)
        medicine.id = UUID()
        medicine.nome = medicineName
        medicine.principio_attivo = ""
        medicine.obbligo_ricetta = false
        medicine.custom_stock_threshold = 0
        medicine.deadline_month = 0
        medicine.deadline_year = 0
        medicine.manual_intake_registration = false
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

        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Mario"
        person.cognome = "Rossi"

        let therapy = Therapy(entity: therapyEntity, insertInto: context)
        therapy.id = UUID()
        therapy.medicine = medicine
        therapy.package = package
        therapy.person = person
        therapy.start_date = makeDate(2026, 2, 11, 0, 0)
        therapy.rrule = "RRULE:FREQ=DAILY"
        therapy.manual_intake_registration = false

        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.time = doseAt
        dose.amount = NSNumber(value: 1)
        dose.therapy = therapy
        therapy.doses = [dose]

        medicine.addToTherapies(therapy)
        return therapy
    }

    private func makeIntakeLog(
        context: NSManagedObjectContext,
        therapy: Therapy,
        timestamp: Date
    ) throws -> Log {
        guard let logEntity = NSEntityDescription.entity(forEntityName: "Log", in: context) else {
            throw NSError(domain: "CriticalDosePlannerTests", code: 2)
        }

        let log = Log(entity: logEntity, insertInto: context)
        log.id = UUID()
        log.type = "intake"
        log.timestamp = timestamp
        log.medicine = therapy.medicine
        log.package = therapy.package
        log.therapy = therapy
        return log
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }
}
