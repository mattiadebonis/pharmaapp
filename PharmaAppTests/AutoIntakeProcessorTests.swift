import Testing
import CoreData
@testable import PharmaApp

@MainActor
struct AutoIntakeProcessorTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal
    }()

    @Test func automaticMedicineIsProcessedEvenWithLegacyGlobalManualOption() throws {
        let context = try makeContext()
        let now = makeDate(2026, 2, 1, 10, 0)
        let doseTime = makeDate(2026, 1, 1, 9, 0)
        let startDate = makeDate(2026, 2, 1, 0, 0)

        let (_, _, therapy) = try makeTherapyGraph(
            in: context,
            medicineManual: false,
            therapyManual: false,
            startDate: startDate,
            doseTime: doseTime
        )
        try insertOption(in: context, manualIntake: true)
        try context.save()

        let processor = AutoIntakeProcessor(context: context, calendar: calendar)
        let created = processor.processDueIntakesBatch(now: now, saveAtEnd: true)
        #expect(created == 1)

        let intakeLogs = try fetchIntakeLogs(in: context, therapy: therapy)
        #expect(intakeLogs.count == 1)
    }

    @Test func manualMedicineIsNotProcessedAutomatically() throws {
        let context = try makeContext()
        let now = makeDate(2026, 2, 1, 10, 0)
        let doseTime = makeDate(2026, 1, 1, 9, 0)
        let startDate = makeDate(2026, 2, 1, 0, 0)

        let (_, _, therapy) = try makeTherapyGraph(
            in: context,
            medicineManual: true,
            therapyManual: false,
            startDate: startDate,
            doseTime: doseTime
        )
        try insertOption(in: context, manualIntake: false)
        try context.save()

        let processor = AutoIntakeProcessor(context: context, calendar: calendar)
        let created = processor.processDueIntakesBatch(now: now, saveAtEnd: true)
        #expect(created == 0)

        let intakeLogs = try fetchIntakeLogs(in: context, therapy: therapy)
        #expect(intakeLogs.isEmpty)
    }

    private func makeContext() throws -> NSManagedObjectContext {
        try TestCoreDataFactory.makeContainer().viewContext
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private func makeTherapyGraph(
        in context: NSManagedObjectContext,
        medicineManual: Bool,
        therapyManual: Bool,
        startDate: Date,
        doseTime: Date
    ) throws -> (Medicine, Package, Therapy) {
        guard let personEntity = NSEntityDescription.entity(forEntityName: "Person", in: context),
              let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(domain: "AutoIntakeProcessorTests", code: 1)
        }

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.manual_intake_registration = medicineManual
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 10)
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.manual_intake_registration = therapyManual
        therapy.package = package
        therapy.start_date = startDate
        therapy.rrule = "RRULE:FREQ=DAILY"

        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Test"
        person.cognome = "User"
        person.is_account = true
        therapy.person = person

        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.time = doseTime
        dose.amount = NSNumber(value: 1)
        dose.therapy = therapy

        return (medicine, package, therapy)
    }

    private func insertOption(in context: NSManagedObjectContext, manualIntake: Bool) throws {
        guard let optionEntity = NSEntityDescription.entity(forEntityName: "Option", in: context) else {
            throw NSError(domain: "AutoIntakeProcessorTests", code: 2)
        }
        let option = Option(entity: optionEntity, insertInto: context)
        option.id = UUID()
        option.manual_intake_registration = manualIntake
        option.day_threeshold_stocks_alarm = 7
        option.therapy_notification_level = TherapyNotificationLevel.normal.rawValue
        option.therapy_snooze_minutes = Int32(TherapyNotificationPreferences.defaultSnoozeMinutes)
        option.prescription_message_template = PrescriptionMessageTemplateRenderer.defaultTemplate
    }

    private func fetchIntakeLogs(in context: NSManagedObjectContext, therapy: Therapy) throws -> [Log] {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.predicate = NSPredicate(format: "type == 'intake' AND therapy == %@", therapy)
        return try context.fetch(request)
    }
}
