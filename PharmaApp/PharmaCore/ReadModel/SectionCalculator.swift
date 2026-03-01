import Foundation

public struct SectionCalculator {
    private let recurrenceService: RecurrencePort
    private let doseScheduleReadModel: DoseScheduleReadModel
    private let clock: Clock
    private let calendar: Calendar

    public init(
        recurrenceService: RecurrencePort,
        doseScheduleReadModel: DoseScheduleReadModel? = nil,
        clock: Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.recurrenceService = recurrenceService
        self.doseScheduleReadModel = doseScheduleReadModel ?? DoseScheduleReadModel(recurrenceService: recurrenceService, calendar: calendar)
        self.clock = clock
        self.calendar = calendar
    }

    public func computeSections(
        for medicines: [MedicineSnapshot],
        option: OptionSnapshot?
    ) -> CabinetSections<MedicineSnapshot> {
        let now = clock.now()

        func remainingUnits(for medicine: MedicineSnapshot) -> Int? {
            if !medicine.therapies.isEmpty {
                return medicine.therapies.reduce(0) { $0 + $1.leftoverUnits }
            }
            return medicine.stockUnitsWithoutTherapy
        }

        func nextOccurrence(for medicine: MedicineSnapshot) -> Date? {
            guard !medicine.therapies.isEmpty else { return nil }

            // Check for pending overdue doses (skipped/not taken)
            let manualTherapies = medicine.therapies.filter {
                $0.manualIntakeRegistration || medicine.manualIntakeRegistration
            }
            if !manualTherapies.isEmpty {
                let intakeLogs = medicine.effectiveIntakeLogs(on: now, calendar: calendar)
                if let missed = doseScheduleReadModel.missedDoseCandidate(
                    for: manualTherapies,
                    intakeLogs: intakeLogs,
                    now: now
                ) {
                    return missed.scheduledAt
                }
            }

            // Fall back to recurrence-based next occurrence
            var best: Date? = nil
            for therapy in medicine.therapies {
                let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
                let startDate = therapy.startDate ?? now
                if let date = recurrenceService.nextOccurrence(
                    rule: rule,
                    startDate: startDate,
                    after: now,
                    doses: therapy.doses,
                    calendar: calendar
                ) {
                    if best == nil || date < best! { best = date }
                }
            }
            return best
        }

        func deadlineDate(for medicine: MedicineSnapshot) -> Date {
            medicine.deadlineMonthStartDate ?? Date.distantFuture
        }

        func occursToday(_ therapy: TherapySnapshot) -> Bool {
            let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.startDate ?? now
            let perDay = max(1, therapy.doses.count)
            let allowed = recurrenceService.allowedEvents(
                on: now,
                rule: rule,
                startDate: start,
                dosesPerDay: perDay,
                calendar: calendar
            )
            return allowed > 0
        }

        func stockStatus(for medicine: MedicineSnapshot) -> StockStatus {
            let threshold = medicine.stockThreshold(option: option)
            if !medicine.therapies.isEmpty {
                var totalLeftover: Double = 0
                var totalDailyUsage: Double = 0
                for therapy in medicine.therapies {
                    totalLeftover += Double(therapy.leftoverUnits)
                    totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
                }
                if totalDailyUsage <= 0 {
                    return totalLeftover > 0 ? .ok : .unknown
                }
                let coverage = totalLeftover / totalDailyUsage
                if coverage <= 0 { return .critical }
                return coverage < Double(threshold) ? .low : .ok
            }
            if let remaining = medicine.stockUnitsWithoutTherapy {
                if remaining <= 0 { return .critical }
                return remaining < threshold ? .low : .ok
            }
            return .unknown
        }

        var purchase: [MedicineSnapshot] = []
        var oggi: [MedicineSnapshot] = []
        var ok: [MedicineSnapshot] = []

        for medicine in medicines {
            let status = stockStatus(for: medicine)
            if status == .critical || status == .low {
                purchase.append(medicine)
                continue
            }
            if !medicine.therapies.isEmpty, medicine.therapies.contains(where: { occursToday($0) }) {
                oggi.append(medicine)
            } else {
                ok.append(medicine)
            }
        }

        oggi.sort { m1, m2 in
            let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
            let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
            if d1 == d2 {
                let r1 = remainingUnits(for: m1) ?? Int.max
                let r2 = remainingUnits(for: m2) ?? Int.max
                if r1 == r2 {
                    let deadline1 = deadlineDate(for: m1)
                    let deadline2 = deadlineDate(for: m2)
                    if deadline1 != deadline2 { return deadline1 < deadline2 }
                    return m1.name.localizedCaseInsensitiveCompare(m2.name) == .orderedAscending
                }
                return r1 < r2
            }
            return d1 < d2
        }

        purchase.sort { m1, m2 in
            let s1 = stockStatus(for: m1)
            let s2 = stockStatus(for: m2)
            if s1 != s2 { return (s1 == .critical) && (s2 != .critical) }
            let r1 = remainingUnits(for: m1) ?? Int.max
            let r2 = remainingUnits(for: m2) ?? Int.max
            if r1 == r2 {
                let deadline1 = deadlineDate(for: m1)
                let deadline2 = deadlineDate(for: m2)
                if deadline1 != deadline2 { return deadline1 < deadline2 }
                return m1.name.localizedCaseInsensitiveCompare(m2.name) == .orderedAscending
            }
            return r1 < r2
        }

        ok.sort { m1, m2 in
            let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
            let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
            if d1 == d2 {
                let r1 = remainingUnits(for: m1) ?? Int.max
                let r2 = remainingUnits(for: m2) ?? Int.max
                if r1 == r2 {
                    let deadline1 = deadlineDate(for: m1)
                    let deadline2 = deadlineDate(for: m2)
                    if deadline1 != deadline2 { return deadline1 < deadline2 }
                    return m1.name.localizedCaseInsensitiveCompare(m2.name) == .orderedAscending
                }
                return r1 < r2
            }
            return d1 < d2
        }

        return CabinetSections(purchase: purchase, oggi: oggi, ok: ok)
    }

    public func stockStatus(for medicine: MedicineSnapshot, option: OptionSnapshot?) -> StockStatus {
        let threshold = medicine.stockThreshold(option: option)
        if !medicine.therapies.isEmpty {
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            for therapy in medicine.therapies {
                totalLeftover += Double(therapy.leftoverUnits)
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
            }
            if totalDailyUsage <= 0 {
                return totalLeftover > 0 ? .ok : .unknown
            }
            let coverage = totalLeftover / totalDailyUsage
            if coverage <= 0 { return .critical }
            return coverage < Double(threshold) ? .low : .ok
        }
        if let remaining = medicine.stockUnitsWithoutTherapy {
            if remaining <= 0 { return .critical }
            return remaining < threshold ? .low : .ok
        }
        return .unknown
    }

    public func isOutOfStock(_ medicine: MedicineSnapshot) -> Bool {
        if !medicine.therapies.isEmpty {
            let totalLeft = medicine.therapies.reduce(0.0) { $0 + Double($1.leftoverUnits) }
            return totalLeft <= 0
        }
        if let remaining = medicine.stockUnitsWithoutTherapy {
            return remaining <= 0
        }
        return false
    }

    public func needsPrescriptionBeforePurchase(_ medicine: MedicineSnapshot, option: OptionSnapshot?) -> Bool {
        guard medicine.requiresPrescription else { return false }
        let hasActivePrescriptionRequest = medicine.logs.contains { log in
            log.type == .prescriptionRequest &&
            log.reversalOfOperationId == nil &&
            !medicine.logs.contains { undo in
                undo.type == .prescriptionRequestUndo &&
                undo.reversalOfOperationId == log.operationId
            }
        }
        if hasActivePrescriptionRequest { return false }

        if !medicine.therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in medicine.therapies {
                totalLeft += Double(therapy.leftoverUnits)
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
            }
            if totalLeft <= 0 { return true }
            guard dailyUsage > 0 else { return false }
            let days = totalLeft / dailyUsage
            let threshold = Double(medicine.stockThreshold(option: option))
            return days < threshold
        }

        if let remaining = medicine.stockUnitsWithoutTherapy {
            return remaining <= medicine.stockThreshold(option: option)
        }
        return false
    }
}
