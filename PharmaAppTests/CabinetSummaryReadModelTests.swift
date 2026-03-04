import Foundation
import Testing
@testable import PharmaApp

struct CabinetSummaryReadModelTests {

    // MARK: - Stub RecurrencePort

    private struct StubRecurrenceService: RecurrencePort {
        func parseRecurrenceString(_ icsString: String) -> RecurrenceRule {
            RecurrenceRule(freq: "DAILY")
        }

        func allowedEvents(
            on day: Date,
            rule: RecurrenceRule,
            startDate: Date,
            dosesPerDay: Int,
            calendar: Calendar
        ) -> Int {
            dosesPerDay
        }

        func nextOccurrence(
            rule: RecurrenceRule,
            startDate: Date,
            after: Date,
            doses: [DoseSnapshot],
            calendar: Calendar
        ) -> Date? {
            nil
        }
    }

    // MARK: - Helpers

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "it_IT")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func makeDate(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int,
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

    private func makeReadModel(calendar: Calendar) -> CabinetSummaryReadModel {
        CabinetSummaryReadModel(
            recurrenceService: StubRecurrenceService(),
            calendar: calendar
        )
    }

    private let defaultOption = OptionSnapshot(
        manualIntakeRegistration: false,
        dayThresholdStocksAlarm: 7
    )

    private let defaultPharmacy = PharmacyInfo(
        name: "Farmacia San Martino",
        isOpen: true,
        distanceText: "4 min"
    )

    private func makeMedicine(
        name: String = "Tachipirina",
        manualIntake: Bool = true,
        therapies: [TherapySnapshot] = [],
        logs: [LogEntry] = [],
        stockUnitsWithoutTherapy: Int? = nil
    ) -> MedicineSnapshot {
        MedicineSnapshot(
            id: MedicineId(UUID()),
            externalKey: UUID().uuidString,
            name: name,
            requiresPrescription: false,
            inCabinet: true,
            manualIntakeRegistration: manualIntake,
            hasPackages: true,
            hasMedicinePackages: true,
            deadlineMonth: nil,
            deadlineYear: nil,
            stockUnitsWithoutTherapy: stockUnitsWithoutTherapy,
            therapies: therapies,
            logs: logs
        )
    }

    private func makeTherapy(
        medicineId: MedicineId = MedicineId(UUID()),
        startDate: Date,
        doseTimes: [Date],
        leftoverUnits: Int,
        manualIntake: Bool = true,
        calendar: Calendar
    ) -> TherapySnapshot {
        let doses = doseTimes.map { DoseSnapshot(time: $0, amount: 1.0) }
        return TherapySnapshot(
            id: TherapyId(UUID()),
            externalKey: UUID().uuidString,
            medicineId: medicineId,
            packageId: PackageId(UUID()),
            packageKey: UUID().uuidString,
            startDate: startDate,
            rrule: "RRULE:FREQ=DAILY",
            doses: doses,
            leftoverUnits: leftoverUnits,
            manualIntakeRegistration: manualIntake,
            clinicalRules: nil,
            personName: nil
        )
    }

    private func makeIntakeLog(
        at timestamp: Date,
        therapyId: TherapyId? = nil,
        scheduledDueAt: Date? = nil
    ) -> LogEntry {
        LogEntry(
            type: .intake,
            timestamp: timestamp,
            scheduledDueAt: scheduledDueAt,
            operationId: UUID(),
            reversalOfOperationId: nil,
            therapyId: therapyId,
            packageId: nil
        )
    }

    // MARK: - Scenario 1: Missed dose

    @Test func missedDoseShowsEarliestTime() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 10, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [
                makeDate(2026, 3, 1, 8, 0, calendar: calendar),
                makeDate(2026, 3, 1, 12, 0, calendar: calendar)
            ],
            leftoverUnits: 20,
            calendar: calendar
        )

        let medicine = makeMedicine(therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(summary.priority == .missedDose)
        #expect(summary.state == .critical)
        #expect(summary.title == "Una terapia di oggi richiede attenzione.")
        #expect(summary.subtitle.contains("08:00"))
        #expect(!summary.subtitle.contains("farmacia"))
    }

    // MARK: - Scenario 2: Missed dose + stock issue

    @Test func missedDoseWithStockIssueShowsPharmacy() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 10, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 8, 30, calendar: calendar)],
            leftoverUnits: 2,
            calendar: calendar
        )

        let medicine = makeMedicine(therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(summary.priority == .missedDose)
        #expect(summary.subtitle.contains("08:30"))
        #expect(summary.subtitle.contains("farmacia vicina a 4 min"))
    }

    // MARK: - Scenario 3: Refill needed before next dose

    @Test func refillBeforeNextDoseShowsNextDoseTime() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 20, 30, calendar: calendar)],
            leftoverUnits: 0,
            manualIntake: false,
            calendar: calendar
        )

        let medicine = makeMedicine(manualIntake: false, therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(summary.priority == .refillBeforeNextDose)
        #expect(summary.state == .critical)
        #expect(summary.title == "Serve un rifornimento prima della prossima assunzione.")
        #expect(summary.subtitle.contains("20:30"))
        #expect(summary.subtitle.contains("farmacia vicina a 4 min"))
    }

    @Test func refillBeforeNextDosePluralizesForMultipleMedicines() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapyA = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 20, 30, calendar: calendar)],
            leftoverUnits: 0,
            manualIntake: false,
            calendar: calendar
        )
        let medicineA = makeMedicine(name: "Aspirina", manualIntake: false, therapies: [therapyA])

        let therapyB = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 21, 0, calendar: calendar)],
            leftoverUnits: 0,
            manualIntake: false,
            calendar: calendar
        )
        let medicineB = makeMedicine(name: "Moment", manualIntake: false, therapies: [therapyB])

        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicineA, medicineB],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(summary.priority == .refillBeforeNextDose)
        #expect(summary.title == "2 farmaci in terapia oggi necessitano di rifornimento.")
    }

    // MARK: - Scenario 4: Imminent dose (within 60 min)

    @Test func imminentDoseShowsMinutesAway() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 19, 50, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [
                makeDate(2026, 3, 1, 8, 0, calendar: calendar),
                makeDate(2026, 3, 1, 20, 30, calendar: calendar)
            ],
            leftoverUnits: 20,
            calendar: calendar
        )
        let therapyId = therapy.id
        let intakeLog = makeIntakeLog(
            at: makeDate(2026, 3, 1, 8, 5, calendar: calendar),
            therapyId: therapyId,
            scheduledDueAt: makeDate(2026, 3, 1, 8, 0, calendar: calendar)
        )

        let medicine = makeMedicine(therapies: [therapy], logs: [intakeLog])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(summary.priority == .imminentDose)
        #expect(summary.state == .warning)
        #expect(summary.title == "Prossima assunzione tra 40 minuti.")
        #expect(summary.subtitle == "È prevista alle 20:30.")
    }

    @Test func imminentDoseBeatsRefillSoon() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 19, 50, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        // Medicine A: pending dose in 40 min, plenty of stock
        let therapyA = makeTherapy(
            startDate: startDate,
            doseTimes: [
                makeDate(2026, 3, 1, 8, 0, calendar: calendar),
                makeDate(2026, 3, 1, 20, 30, calendar: calendar)
            ],
            leftoverUnits: 20,
            calendar: calendar
        )
        let therapyAId = therapyA.id
        let intakeLogA = makeIntakeLog(
            at: makeDate(2026, 3, 1, 8, 5, calendar: calendar),
            therapyId: therapyAId,
            scheduledDueAt: makeDate(2026, 3, 1, 8, 0, calendar: calendar)
        )
        let medicineA = makeMedicine(name: "Aspirina", therapies: [therapyA], logs: [intakeLogA])

        // Medicine B: low stock (5 units, under threshold 7), no manual intake
        let therapyB = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 8, 0, calendar: calendar)],
            leftoverUnits: 5,
            manualIntake: false,
            calendar: calendar
        )
        let medicineB = makeMedicine(name: "Moment", manualIntake: false, therapies: [therapyB])

        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicineA, medicineB],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(summary.priority == .imminentDose)
        #expect(summary.state == .warning)
        #expect(summary.title.contains("tra 40 minuti"))
    }

    @Test func refillBeforeNextDoseBeatsImminentDose() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 20, 10, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        // Medicine with pending dose in 20 min AND empty stock (critical refill)
        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 20, 30, calendar: calendar)],
            leftoverUnits: 0,
            calendar: calendar
        )

        let medicine = makeMedicine(therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        // refillBeforeNextDose is critical and beats imminentDose
        #expect(summary.priority == .refillBeforeNextDose)
        #expect(summary.state == .critical)
    }

    @Test func doseOutside60MinWindowIsNotImminent() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        // Dose at 20:30 — 6.5 hours away, well outside 60 min window
        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [
                makeDate(2026, 3, 1, 8, 0, calendar: calendar),
                makeDate(2026, 3, 1, 20, 30, calendar: calendar)
            ],
            leftoverUnits: 20,
            calendar: calendar
        )
        let therapyId = therapy.id
        let intakeLog = makeIntakeLog(
            at: makeDate(2026, 3, 1, 8, 5, calendar: calendar),
            therapyId: therapyId,
            scheduledDueAt: makeDate(2026, 3, 1, 8, 0, calendar: calendar)
        )

        let medicine = makeMedicine(therapies: [therapy], logs: [intakeLog])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        // Should fall to nextDoseToday, not imminentDose
        #expect(summary.priority == .nextDoseToday)
        #expect(summary.state == .info)
    }

    // MARK: - Scenario 5: Refill within today beats next dose today

    @Test func refillWithinTodayBeatsNextDoseToday() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        // Medicine A: has pending dose, plenty of stock
        let therapyA = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 20, 30, calendar: calendar)],
            leftoverUnits: 20,
            calendar: calendar
        )
        let medicineA = makeMedicine(name: "Aspirina", therapies: [therapyA])

        // Medicine B: low stock (1 unit), covers next dose but runs out within today
        let therapyB = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 20, 30, calendar: calendar)],
            leftoverUnits: 1,
            manualIntake: false,
            calendar: calendar
        )
        let medicineB = makeMedicine(name: "Moment", manualIntake: false, therapies: [therapyB])

        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicineA, medicineB],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(summary.priority == .refillWithinToday)
        #expect(summary.state == .warning)
        #expect(summary.title.contains("Per le terapie in corso"))
        #expect(summary.title.contains("rifornito entro oggi"))
        #expect(summary.subtitle.contains("farmacia più vicina"))
    }

    // MARK: - Scenario 6: Next dose today (no stock issues)

    @Test func nextDoseTodayShowsPendingCount() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [
                makeDate(2026, 3, 1, 8, 0, calendar: calendar),
                makeDate(2026, 3, 1, 16, 0, calendar: calendar),
                makeDate(2026, 3, 1, 20, 30, calendar: calendar)
            ],
            leftoverUnits: 100,
            calendar: calendar
        )

        let therapyId = therapy.id
        let intakeLog = makeIntakeLog(
            at: makeDate(2026, 3, 1, 8, 5, calendar: calendar),
            therapyId: therapyId,
            scheduledDueAt: makeDate(2026, 3, 1, 8, 0, calendar: calendar)
        )

        let medicine = makeMedicine(therapies: [therapy], logs: [intakeLog])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(summary.priority == .nextDoseToday)
        #expect(summary.state == .info)
        #expect(summary.title.contains("2"))
        #expect(summary.subtitle.contains("16:00"))
    }

    // MARK: - Scenario 7: Next dose today alone (clean subtitle, no refill clause)

    @Test func nextDoseTodayAloneShowsCleanSubtitle() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [
                makeDate(2026, 3, 1, 8, 0, calendar: calendar),
                makeDate(2026, 3, 1, 20, 30, calendar: calendar)
            ],
            leftoverUnits: 20,
            calendar: calendar
        )
        let therapyId = therapy.id
        let intakeLog = makeIntakeLog(
            at: makeDate(2026, 3, 1, 8, 5, calendar: calendar),
            therapyId: therapyId,
            scheduledDueAt: makeDate(2026, 3, 1, 8, 0, calendar: calendar)
        )

        let medicine = makeMedicine(therapies: [therapy], logs: [intakeLog])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(summary.priority == .nextDoseToday)
        #expect(summary.state == .info)
        #expect(summary.title == "Oggi resta 1 assunzione da completare.")
        #expect(summary.subtitle == "La prossima è prevista alle 20:30.")
        #expect(!summary.subtitle.contains("rifornit"))
    }

    // MARK: - Scenario 8: Refill soon

    @Test func refillSoonShowsCount() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 8, 0, calendar: calendar)],
            leftoverUnits: 5,
            manualIntake: false,
            calendar: calendar
        )

        let medicine = makeMedicine(manualIntake: false, therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(summary.priority == .refillSoon)
        #expect(summary.state == .info)
        #expect(summary.title.contains("Le terapie sono coperte"))
        #expect(summary.title.contains("rifornimento a breve"))
        #expect(summary.subtitle.contains("farmacia più vicina"))
    }

    // MARK: - Scenario 9: Refill soon beats next dose today

    @Test func refillSoonBeatsNextDoseToday() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        // Medicine A: has pending dose, plenty of stock
        let therapyA = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 20, 30, calendar: calendar)],
            leftoverUnits: 20,
            calendar: calendar
        )
        let medicineA = makeMedicine(name: "Aspirina", therapies: [therapyA])

        // Medicine B: low stock (5 units, under threshold 7), no manual intake
        let therapyB = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 8, 0, calendar: calendar)],
            leftoverUnits: 5,
            manualIntake: false,
            calendar: calendar
        )
        let medicineB = makeMedicine(name: "Moment", manualIntake: false, therapies: [therapyB])

        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicineA, medicineB],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(summary.priority == .refillSoon)
        #expect(summary.state == .info)
        #expect(summary.title.contains("rifornimento a breve"))
    }

    // MARK: - Inline action

    @Test func inlineMissedDoseShowsTimeAndMedicine() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 10, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [
                makeDate(2026, 3, 1, 8, 0, calendar: calendar),
                makeDate(2026, 3, 1, 20, 0, calendar: calendar)
            ],
            leftoverUnits: 20,
            calendar: calendar
        )

        let medicine = makeMedicine(name: "tachipirina", therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let inlineAction = readModel.buildInlineAction(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(inlineAction.priority == .missedDose)
        #expect(inlineAction.text == "08:00 dose saltata: Tachipirina")
    }

    @Test func inlineNextDoseShowsTimeAndMedicine() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [
                makeDate(2026, 3, 1, 8, 0, calendar: calendar),
                makeDate(2026, 3, 1, 16, 0, calendar: calendar)
            ],
            leftoverUnits: 20,
            calendar: calendar
        )
        let therapyId = therapy.id
        let intakeLog = makeIntakeLog(
            at: makeDate(2026, 3, 1, 8, 5, calendar: calendar),
            therapyId: therapyId,
            scheduledDueAt: makeDate(2026, 3, 1, 8, 0, calendar: calendar)
        )

        let medicine = makeMedicine(name: "aspirina", therapies: [therapy], logs: [intakeLog])
        let readModel = makeReadModel(calendar: calendar)

        let inlineAction = readModel.buildInlineAction(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(inlineAction.priority == .nextDoseToday)
        #expect(inlineAction.text == "16:00 prendi Aspirina")
    }

    @Test func inlineRefillBeforeNextDoseShowsMedicineAndTime() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 20, 30, calendar: calendar)],
            leftoverUnits: 0,
            manualIntake: false,
            calendar: calendar
        )

        let medicine = makeMedicine(name: "moment", manualIntake: false, therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let inlineAction = readModel.buildInlineAction(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(inlineAction.priority == .refillBeforeNextDose)
        #expect(inlineAction.text == "20:30 rifornisci Moment")
    }

    @Test func inlineRefillWithinTodayShowsSingleAction() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 20, 30, calendar: calendar)],
            leftoverUnits: 1,
            manualIntake: false,
            calendar: calendar
        )

        let medicine = makeMedicine(name: "moment", manualIntake: false, therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let inlineAction = readModel.buildInlineAction(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(inlineAction.priority == .refillWithinToday)
        #expect(inlineAction.text == "Oggi rifornisci Moment")
    }

    // MARK: - Scenario 10: All under control

    @Test func allUnderControlWhenEverythingIsOk() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 8, 0, calendar: calendar)],
            leftoverUnits: 100,
            manualIntake: false,
            calendar: calendar
        )

        let medicine = makeMedicine(manualIntake: false, therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(summary.priority == .allUnderControl)
        #expect(summary.state == .ok)
        #expect(summary.title == "Tutto sotto controllo.")
    }

    // MARK: - Backward compatibility

    @Test func buildLinesReturnsTitleAndSubtitle() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 14, 0, calendar: calendar)

        let readModel = makeReadModel(calendar: calendar)
        let lines = readModel.buildLines(
            medicines: [],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(lines.count == 2)
        #expect(lines[0] == "Tutto sotto controllo.")
        #expect(lines[1] == "Le terapie sono coperte e le scorte sono adeguate.")
    }

    // MARK: - No option provided

    @Test func noOptionReturnsAllUnderControl() {
        let calendar = makeCalendar()
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [],
            option: nil,
            pharmacy: nil
        )

        #expect(summary.priority == .allUnderControl)
        #expect(summary.title == "Tutto sotto controllo.")
    }

    // MARK: - Medicine names never in summary

    @Test func summaryNeverContainsMedicineNames() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 10, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let therapy = makeTherapy(
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 8, 0, calendar: calendar)],
            leftoverUnits: 2,
            calendar: calendar
        )

        let medicine = makeMedicine(name: "Tachipirina", therapies: [therapy])
        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicine],
            option: defaultOption,
            pharmacy: defaultPharmacy,
            now: now
        )

        #expect(!summary.title.contains("Tachipirina"))
        #expect(!summary.subtitle.contains("Tachipirina"))
    }

    // MARK: - Multiple missed doses shows earliest

    @Test func multipleMissedDosesShowsEarliestTime() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 1, 15, 0, calendar: calendar)
        let startDate = makeDate(2026, 2, 28, 8, 0, calendar: calendar)

        let medicineAId = MedicineId(UUID())
        let therapyA = makeTherapy(
            medicineId: medicineAId,
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 12, 0, calendar: calendar)],
            leftoverUnits: 20,
            calendar: calendar
        )
        let medicineA = makeMedicine(name: "Aspirina", therapies: [therapyA])

        let medicineBId = MedicineId(UUID())
        let therapyB = makeTherapy(
            medicineId: medicineBId,
            startDate: startDate,
            doseTimes: [makeDate(2026, 3, 1, 8, 0, calendar: calendar)],
            leftoverUnits: 20,
            calendar: calendar
        )
        let medicineB = makeMedicine(name: "Moment", therapies: [therapyB])

        let readModel = makeReadModel(calendar: calendar)

        let summary = readModel.buildSummary(
            medicines: [medicineA, medicineB],
            option: defaultOption,
            pharmacy: nil,
            now: now
        )

        #expect(summary.priority == .missedDose)
        #expect(summary.subtitle.contains("08:00"))
        #expect(!summary.subtitle.contains("12:00"))
    }
}
