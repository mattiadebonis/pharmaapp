import Foundation
import CoreData
import Testing
@testable import PharmaApp

private final class ActionSnoozeStoreFake: CriticalDoseSnoozeStoreProtocol {
    var snoozeCalls: [(therapyId: UUID, scheduledAt: Date, now: Date, duration: TimeInterval)] = []
    var clearedKeys: [String] = []

    func isSnoozed(therapyId: UUID, scheduledAt: Date, now: Date) -> Bool { false }

    @discardableResult
    func snooze(therapyId: UUID, scheduledAt: Date, now: Date, duration: TimeInterval) -> Date {
        snoozeCalls.append((therapyId, scheduledAt, now, duration))
        return now.addingTimeInterval(duration)
    }

    func clear(therapyId: UUID, scheduledAt: Date) {
        let bucket = Int(scheduledAt.timeIntervalSince1970 / 60)
        clearedKeys.append("\(therapyId.uuidString)|\(bucket)")
    }

    func nextExpiry(after now: Date) -> Date? { nil }
}

private final class ActionReminderSchedulerFake: CriticalDoseReminderScheduling {
    var scheduled: [(state: CriticalDoseLiveActivityAttributes.ContentState, remindAt: Date, now: Date)] = []

    func scheduleReminder(
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        remindAt: Date,
        now: Date
    ) async {
        scheduled.append((contentState, remindAt, now))
    }
}

private final class InMemoryOperationProvider: OperationIdProviding {
    private var storage: [String: UUID] = [:]

    func operationId(for key: OperationKey, ttl: TimeInterval) -> UUID {
        if let existing = storage[key.rawValue] {
            return existing
        }
        let id = UUID()
        storage[key.rawValue] = id
        return id
    }

    func clear(_ key: OperationKey) {
        storage.removeValue(forKey: key.rawValue)
    }

    func newOperationId() -> UUID { UUID() }
}

@MainActor
struct CriticalDoseActionServiceTests {
    @Test func markTakenIsIdempotentForSameDose() throws {
        let context = try TestCoreDataFactory.makeContainer().viewContext
        let therapy = try makeTherapy(context: context)
        try context.save()

        let snooze = ActionSnoozeStoreFake()
        let reminder = ActionReminderSchedulerFake()
        let operationProvider = InMemoryOperationProvider()
        let service = CriticalDoseActionService(
            context: context,
            snoozeStore: snooze,
            reminderScheduler: reminder,
            operationIdProvider: operationProvider
        )

        let scheduledAt = makeDate(2026, 2, 11, 10, 15)
        let state = makeState(therapy: therapy, scheduledAt: scheduledAt)

        let first = service.markTaken(contentState: state)
        let second = service.markTaken(contentState: state)

        #expect(first == true)
        #expect(second == true)
        #expect(therapy.medicine.effectiveIntakeLogs().count == 1)
    }

    @Test func remindLaterStoresSnoozeAndSchedulesReminder() async throws {
        let context = try TestCoreDataFactory.makeContainer().viewContext
        let therapy = try makeTherapy(context: context)
        try context.save()

        let snooze = ActionSnoozeStoreFake()
        let reminder = ActionReminderSchedulerFake()
        let service = CriticalDoseActionService(
            context: context,
            snoozeStore: snooze,
            reminderScheduler: reminder,
            operationIdProvider: InMemoryOperationProvider()
        )

        let now = makeDate(2026, 2, 11, 10, 0)
        let scheduledAt = makeDate(2026, 2, 11, 10, 20)
        let state = makeState(therapy: therapy, scheduledAt: scheduledAt)

        let success = await service.remindLater(contentState: state, now: now)

        #expect(success == true)
        #expect(snooze.snoozeCalls.count == 1)
        #expect(snooze.snoozeCalls[0].duration == 600)
        #expect(reminder.scheduled.count == 1)
        #expect(reminder.scheduled[0].remindAt == now.addingTimeInterval(600))
    }

    private func makeState(therapy: Therapy, scheduledAt: Date) -> CriticalDoseLiveActivityAttributes.ContentState {
        CriticalDoseLiveActivityAttributes.ContentState(
            primaryTherapyId: therapy.id.uuidString,
            primaryMedicineId: therapy.medicine.id.uuidString,
            primaryMedicineName: therapy.medicine.nome,
            primaryDoseText: "1 compressa",
            primaryScheduledAt: scheduledAt,
            additionalCount: 0,
            subtitleDisplay: "\(therapy.medicine.nome) · 1 compressa",
            expiryAt: scheduledAt.addingTimeInterval(1800)
        )
    }

    private func makeTherapy(context: NSManagedObjectContext) throws -> Therapy {
        guard let medicineEntity = NSEntityDescription.entity(forEntityName: "Medicine", in: context),
              let packageEntity = NSEntityDescription.entity(forEntityName: "Package", in: context),
              let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context),
              let therapyEntity = NSEntityDescription.entity(forEntityName: "Therapy", in: context),
              let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(domain: "CriticalDoseActionTests", code: 1)
        }

        let medicine = Medicine(entity: medicineEntity, insertInto: context)
        medicine.id = UUID()
        medicine.nome = "Othargan 5"
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
        person.nome = "Luca"
        person.cognome = "Bianchi"

        let therapy = Therapy(entity: therapyEntity, insertInto: context)
        therapy.id = UUID()
        therapy.medicine = medicine
        therapy.package = package
        therapy.person = person
        therapy.start_date = makeDate(2026, 2, 11, 0, 0)
        therapy.rrule = "RRULE:FREQ=DAILY"
        therapy.manual_intake_registration = true

        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.time = makeDate(2026, 2, 11, 10, 15)
        dose.amount = NSNumber(value: 1)
        dose.therapy = therapy
        therapy.doses = [dose]

        medicine.addToTherapies(therapy)
        return therapy
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
