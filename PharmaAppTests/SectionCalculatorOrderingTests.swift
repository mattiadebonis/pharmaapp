import Foundation
import Testing
@testable import PharmaApp

struct SectionCalculatorOrderingTests {
    private struct FrozenClock: Clock {
        let date: Date
        func now() -> Date { date }
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

    private func makeMedicine(
        name: String,
        doseTime: Date,
        now: Date,
        calendar: Calendar,
        leftoverUnits: Int
    ) -> MedicineSnapshot {
        let medicineId = MedicineId(UUID())
        let therapy = TherapySnapshot(
            id: TherapyId(UUID()),
            externalKey: UUID().uuidString,
            medicineId: medicineId,
            packageId: PackageId(UUID()),
            packageKey: UUID().uuidString,
            startDate: calendar.startOfDay(for: now),
            rrule: "RRULE:FREQ=DAILY;INTERVAL=1",
            doses: [DoseSnapshot(time: doseTime, amount: 1)],
            leftoverUnits: leftoverUnits,
            manualIntakeRegistration: false,
            clinicalRules: nil,
            personName: nil
        )

        return MedicineSnapshot(
            id: medicineId,
            externalKey: UUID().uuidString,
            name: name,
            requiresPrescription: false,
            inCabinet: true,
            manualIntakeRegistration: false,
            hasPackages: true,
            hasMedicinePackages: true,
            deadlineMonth: nil,
            deadlineYear: nil,
            stockUnitsWithoutTherapy: nil,
            therapies: [therapy],
            logs: []
        )
    }

    @Test
    func sameDaySortingUsesIntakeTimeBeforeStockDrivenPriority() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 5, 0, 30, calendar: calendar)
        let morningDose = makeDate(2026, 3, 5, 9, 0, calendar: calendar)
        let eveningDose = makeDate(2026, 3, 5, 20, 0, calendar: calendar)

        let lowStockEvening = makeMedicine(
            name: "Evening",
            doseTime: eveningDose,
            now: now,
            calendar: calendar,
            leftoverUnits: 2
        )
        let okStockMorning = makeMedicine(
            name: "Morning",
            doseTime: morningDose,
            now: now,
            calendar: calendar,
            leftoverUnits: 40
        )

        let calculator = SectionCalculator(
            recurrenceService: PureRecurrenceService(),
            clock: FrozenClock(date: now),
            calendar: calendar
        )
        let option = OptionSnapshot(
            manualIntakeRegistration: false,
            dayThresholdStocksAlarm: 7
        )

        let sorted = calculator.prioritySortedMedicines(
            for: [lowStockEvening, okStockMorning],
            option: option
        )

        #expect(sorted.map(\.name) == ["Morning", "Evening"])
    }
}
