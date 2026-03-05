import XCTest
import CoreData
@testable import PharmaApp

final class DataManagerOptionsBootstrapTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testInitializeOptionsIfEmptyCreatesOptionWithDefaultPrescriptionTemplate() throws {
        let manager = DataManager(context: context)

        manager.initializeOptionsIfEmpty()

        let options = try fetchOptions()
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.prescription_message_template, PrescriptionMessageTemplateRenderer.defaultTemplate)
    }

    func testInitializeOptionsIfEmptyPopulatesDefaultTemplateWhenMissing() throws {
        let option = makeOption(
            template: nil,
            dayThreshold: 7,
            manualIntake: false,
            therapyLevel: TherapyNotificationPreferences.defaultLevel.rawValue,
            snoozeMinutes: Int32(TherapyNotificationPreferences.defaultSnoozeMinutes)
        )
        _ = option
        try context.save()

        let manager = DataManager(context: context)
        manager.initializeOptionsIfEmpty()

        let options = try fetchOptions()
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.prescription_message_template, PrescriptionMessageTemplateRenderer.defaultTemplate)
    }

    func testInitializeOptionsIfEmptyDoesNotOverrideCustomTemplate() throws {
        let customTemplate = "Gentile {medico}, ricetta per {medicinali}."
        let option = makeOption(
            template: customTemplate,
            dayThreshold: 7,
            manualIntake: true,
            therapyLevel: TherapyNotificationPreferences.defaultLevel.rawValue,
            snoozeMinutes: Int32(TherapyNotificationPreferences.defaultSnoozeMinutes)
        )
        _ = option
        try context.save()

        let manager = DataManager(context: context)
        manager.initializeOptionsIfEmpty()

        let options = try fetchOptions()
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.prescription_message_template, customTemplate)
    }

    func testMigrateDeadlineToEntryCopiesLegacyDeadlineToAllEntriesWithoutDeadline() throws {
        let manager = DataManager(context: context)
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.deadline_month = 4
        medicine.deadline_year = 2029
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let entryOne = try TestCoreDataFactory.makeMedicinePackage(context: context, medicine: medicine, package: package)
        let entryTwo = try TestCoreDataFactory.makeMedicinePackage(context: context, medicine: medicine, package: package)
        entryTwo.updateDeadline(month: 6, year: 2030)
        try context.save()

        let defaults = makeEphemeralUserDefaults()
        manager.migrateDeadlineToEntryIfNeeded(userDefaults: defaults)

        XCTAssertEqual(entryOne.deadlineMonthYear?.month, 4)
        XCTAssertEqual(entryOne.deadlineMonthYear?.year, 2029)
        XCTAssertEqual(entryTwo.deadlineMonthYear?.month, 6)
        XCTAssertEqual(entryTwo.deadlineMonthYear?.year, 2030)
    }

    func testMigrateDeadlineToEntryIsIdempotent() throws {
        let manager = DataManager(context: context)
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.deadline_month = 9
        medicine.deadline_year = 2031
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let entry = try TestCoreDataFactory.makeMedicinePackage(context: context, medicine: medicine, package: package)
        try context.save()

        let defaults = makeEphemeralUserDefaults()
        manager.migrateDeadlineToEntryIfNeeded(userDefaults: defaults)
        XCTAssertEqual(entry.deadlineMonthYear?.month, 9)
        XCTAssertEqual(entry.deadlineMonthYear?.year, 2031)

        medicine.deadline_month = 11
        medicine.deadline_year = 2032
        try context.save()
        manager.migrateDeadlineToEntryIfNeeded(userDefaults: defaults)

        XCTAssertEqual(entry.deadlineMonthYear?.month, 9)
        XCTAssertEqual(entry.deadlineMonthYear?.year, 2031)
    }

    private func fetchOptions() throws -> [Option] {
        let request: NSFetchRequest<Option> = Option.fetchRequest()
        return try context.fetch(request)
    }

    private func makeEphemeralUserDefaults() -> UserDefaults {
        let suiteName = "DataManagerOptionsBootstrapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @discardableResult
    private func makeOption(
        template: String?,
        dayThreshold: Int32,
        manualIntake: Bool,
        therapyLevel: String,
        snoozeMinutes: Int32
    ) -> Option {
        guard let optionEntity = NSEntityDescription.entity(forEntityName: "Option", in: context) else {
            XCTFail("Entity Option non trovata nel contesto di test")
            fatalError("Entity Option non trovata nel contesto di test")
        }
        let option = Option(entity: optionEntity, insertInto: context)
        option.id = UUID()
        option.manual_intake_registration = manualIntake
        option.day_threeshold_stocks_alarm = dayThreshold
        option.therapy_notification_level = therapyLevel
        option.therapy_snooze_minutes = snoozeMinutes
        option.prescription_message_template = template
        return option
    }
}
