import Foundation
import CoreData
import Testing
@testable import PharmaApp

struct CabinetSummaryBuilderTests {
    @MainActor
    @Test func summaryOmitsPharmacySuggestionWhenNoPharmacyIsAvailable() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()
        let option = try makeOption(context: context)

        let firstMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        firstMedicine.nome = "tachipirina"
        let firstPackage = try TestCoreDataFactory.makePackage(context: context, medicine: firstMedicine)
        _ = try makeDailyTherapy(
            context: context,
            medicine: firstMedicine,
            package: firstPackage,
            doseTimes: [makeDate(2026, 2, 28, 8, 0, calendar: calendar)]
        )

        let secondMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        secondMedicine.nome = "aspirina"
        let secondPackage = try TestCoreDataFactory.makePackage(context: context, medicine: secondMedicine)
        _ = try makeDailyTherapy(
            context: context,
            medicine: secondMedicine,
            package: secondPackage,
            doseTimes: [makeDate(2026, 2, 28, 9, 0, calendar: calendar)]
        )

        let stockService = StockService(context: context)
        stockService.setUnits(2, for: firstPackage)
        stockService.setUnits(5, for: secondPackage)

        let builder = CabinetSummaryBuilder(
            recurrenceManager: RecurrenceManager(context: context),
            calendar: calendar
        )

        let lines = builder.buildLines(
            medicines: [firstMedicine, secondMedicine],
            option: option,
            pharmacy: nil,
            now: makeDate(2026, 2, 28, 10, 0, calendar: calendar)
        )

        #expect(lines == [
            "Tachipirina e Aspirina sono in esaurimento",
            "Terapie in regola"
        ])
    }

    @MainActor
    @Test func summaryTreatsZeroUnitsWithoutTherapyAsLowStock() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()
        let option = try makeOption(context: context)

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "moment"
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        let stockService = StockService(context: context)
        stockService.setUnits(0, for: package)

        let builder = CabinetSummaryBuilder(
            recurrenceManager: RecurrenceManager(context: context),
            calendar: calendar
        )

        let lines = builder.buildLines(
            medicines: [medicine],
            option: option,
            pharmacy: nil,
            now: makeDate(2026, 2, 28, 10, 0, calendar: calendar)
        )

        #expect(lines == [
            "Moment è in esaurimento",
            "Terapie in regola"
        ])
    }

    @MainActor
    @Test func summaryShowsPharmacyRefillSentenceWithStatusAndTravelTimes() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()
        let option = try makeOption(context: context)

        let firstMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        firstMedicine.nome = "otalgan"
        let firstPackage = try TestCoreDataFactory.makePackage(context: context, medicine: firstMedicine)
        _ = try makeDailyTherapy(
            context: context,
            medicine: firstMedicine,
            package: firstPackage,
            doseTimes: [makeDate(2026, 2, 28, 8, 0, calendar: calendar)]
        )

        let secondMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        secondMedicine.nome = "rinocidina"
        let secondPackage = try TestCoreDataFactory.makePackage(context: context, medicine: secondMedicine)
        _ = try makeDailyTherapy(
            context: context,
            medicine: secondMedicine,
            package: secondPackage,
            doseTimes: [makeDate(2026, 2, 28, 9, 0, calendar: calendar)]
        )

        let stockService = StockService(context: context)
        stockService.setUnits(2, for: firstPackage)
        stockService.setUnits(1, for: secondPackage)

        let builder = CabinetSummaryBuilder(
            recurrenceManager: RecurrenceManager(context: context),
            calendar: calendar
        )

        let lines = builder.buildLines(
            medicines: [firstMedicine, secondMedicine],
            option: option,
            pharmacy: CabinetSummaryPharmacyInfo(
                name: "Farmacia San Martino",
                isOpen: true,
                distanceText: "2 min a piedi · 1 min in auto"
            ),
            now: makeDate(2026, 2, 28, 10, 0, calendar: calendar)
        )

        #expect(lines == [
            "Otalgan e Rinocidina sono in esaurimento e puoi rifornirli presso Farmacia San Martino, aperta a 2 min a piedi o 1 min in auto",
            "Terapie in regola"
        ])
    }

    @MainActor
    @Test func summaryOmitsPharmacySuggestionWhenPharmacyNameIsMissing() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()
        let option = try makeOption(context: context)

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "moment"
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        let stockService = StockService(context: context)
        stockService.setUnits(0, for: package)

        let builder = CabinetSummaryBuilder(
            recurrenceManager: RecurrenceManager(context: context),
            calendar: calendar
        )

        let lines = builder.buildLines(
            medicines: [medicine],
            option: option,
            pharmacy: CabinetSummaryPharmacyInfo(
                name: " ",
                isOpen: true,
                distanceText: "500 m"
            ),
            now: makeDate(2026, 2, 28, 10, 0, calendar: calendar)
        )

        #expect(lines == [
            "Moment è in esaurimento",
            "Terapie in regola"
        ])
    }

    @MainActor
    @Test func summaryShowsMissedMedicineAndDoseCounts() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()
        let option = try makeOption(context: context)

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Tachipirina"
        medicine.manual_intake_registration = true
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        _ = try makeDailyTherapy(
            context: context,
            medicine: medicine,
            package: package,
            doseTimes: [
                makeDate(2026, 2, 28, 8, 0, calendar: calendar),
                makeDate(2026, 2, 28, 20, 0, calendar: calendar)
            ]
        )

        let stockService = StockService(context: context)
        stockService.setUnits(20, for: package)

        let builder = CabinetSummaryBuilder(
            recurrenceManager: RecurrenceManager(context: context),
            calendar: calendar
        )

        let lines = builder.buildLines(
            medicines: [medicine],
            option: option,
            pharmacy: CabinetSummaryPharmacyInfo(
                name: "Farmacia Centrale",
                isOpen: true,
                distanceText: "500 m"
            ),
            now: makeDate(2026, 2, 28, 21, 0, calendar: calendar)
        )

        #expect(lines == [
            "Scorte a posto",
            "Tachipirina ha 2 dosi saltate"
        ])

    }

    @MainActor
    @Test func medicineActiveTherapiesSubtitleShowsOnlyUnitsWhenNoTherapyExists() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let stockService = StockService(context: context)
        stockService.setUnits(200, for: package)

        let payload = makeMedicineActiveTherapiesSubtitle(
            medicine: medicine,
            recurrenceManager: RecurrenceManager(context: context),
            intakeLogsToday: [],
            now: makeDate(2026, 2, 28, 10, 0, calendar: calendar)
        )

        #expect(payload.line1 == "200 unità")
        #expect(payload.line2.isEmpty)
        #expect(payload.therapyLines.isEmpty)
    }

    @MainActor
    @Test func medicineSubtitleShowsUnitsWithoutStockPrefixWhenNoTherapyExists() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let stockService = StockService(context: context)
        stockService.setUnits(200, for: package)

        let subtitle = makeMedicineSubtitle(
            medicine: medicine,
            now: makeDate(2026, 2, 28, 10, 0, calendar: calendar)
        )

        #expect(subtitle.line2 == "200 unità")
    }

    @MainActor
    @Test func medicineDeadlineDisplayShowsRemainingTimeWhenDeadlineIsNear() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.deadline_month = 3
        medicine.deadline_year = 2026

        let display = medicine.deadlineDisplay(
            referenceDate: makeDate(2026, 2, 15, 9, 0, calendar: calendar),
            calendar: calendar
        )

        #expect(display?.label == "Tra 1 mese · 03/2026")
        #expect(display?.status == .expiringSoon)
    }

    @MainActor
    @Test func medicineDeadlineDisplayShowsOnlyDeadlineWhenItIsNotNear() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let calendar = makeCalendar()

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.deadline_month = 6
        medicine.deadline_year = 2026

        let display = medicine.deadlineDisplay(
            referenceDate: makeDate(2026, 2, 15, 9, 0, calendar: calendar),
            calendar: calendar
        )

        #expect(display?.label == "06/2026")
        #expect(display?.status == .ok)
    }

    private func makeOption(context: NSManagedObjectContext) throws -> Option {
        guard let entity = NSEntityDescription.entity(forEntityName: "Option", in: context) else {
            throw NSError(domain: "CabinetSummaryBuilderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Option entity not found"])
        }

        let option = Option(entity: entity, insertInto: context)
        option.id = UUID()
        option.manual_intake_registration = false
        option.day_threeshold_stocks_alarm = 7
        option.therapy_notification_level = nil
        option.therapy_snooze_minutes = 0
        option.prescription_message_template = nil
        return option
    }

    private func makePerson(context: NSManagedObjectContext) throws -> Person {
        guard let entity = NSEntityDescription.entity(forEntityName: "Person", in: context) else {
            throw NSError(domain: "CabinetSummaryBuilderTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Person entity not found"])
        }

        let person = Person(entity: entity, insertInto: context)
        person.id = UUID()
        person.nome = "Mario"
        person.cognome = "Rossi"
        return person
    }

    private func makeDailyTherapy(
        context: NSManagedObjectContext,
        medicine: Medicine,
        package: Package,
        doseTimes: [Date]
    ) throws -> Therapy {
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package
        therapy.person = try makePerson(context: context)
        therapy.start_date = makeDate(2026, 2, 27, 8, 0, calendar: makeCalendar())
        therapy.rrule = "RRULE:FREQ=DAILY"
        therapy.manual_intake_registration = medicine.manual_intake_registration

        guard let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(domain: "CabinetSummaryBuilderTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Dose entity not found"])
        }

        var doses: Set<Dose> = []
        for time in doseTimes {
            let dose = Dose(entity: doseEntity, insertInto: context)
            dose.id = UUID()
            dose.time = time
            dose.amount = NSNumber(value: 1.0)
            dose.therapy = therapy
            doses.insert(dose)
        }
        therapy.doses = doses
        return therapy
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
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }
}
