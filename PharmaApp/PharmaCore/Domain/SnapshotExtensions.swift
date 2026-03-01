import Foundation

// MARK: - MedicineSnapshot extensions

public extension MedicineSnapshot {
    var latestLogSalt: String {
        guard let lastDate = logs.map(\.timestamp).max() else { return "0" }
        return String(Int(lastDate.timeIntervalSince1970 * 1000))
    }

    func stockThreshold(option: OptionSnapshot?) -> Int {
        let value = option?.dayThresholdStocksAlarm ?? 0
        return value > 0 ? value : 7
    }

    func effectiveIntakeLogs(calendar: Calendar = .current) -> [LogEntry] {
        effectiveLogs(type: .intake, undoType: .intakeUndo)
    }

    func effectiveIntakeLogs(on date: Date, calendar: Calendar = .current) -> [LogEntry] {
        effectiveIntakeLogs(calendar: calendar).filter { log in
            calendar.isDate(log.timestamp, inSameDayAs: date)
        }
    }

    func effectivePurchaseLogs() -> [LogEntry] {
        effectiveLogs(type: .purchase, undoType: .purchaseUndo)
    }

    func effectivePrescriptionRequestLogs() -> [LogEntry] {
        effectiveLogs(type: .prescriptionRequest, undoType: .prescriptionRequestUndo)
    }

    func effectivePrescriptionReceivedLogs() -> [LogEntry] {
        effectiveLogs(type: .prescriptionReceived, undoType: .prescriptionReceivedUndo)
    }

    func hasNewPrescriptionRequest() -> Bool {
        let prescriptionLogs = effectivePrescriptionRequestLogs()
        guard !prescriptionLogs.isEmpty else { return false }
        guard let lastPrescription = prescriptionLogs.max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        let purchaseLogsAfterPrescription = effectivePurchaseLogs().filter { $0.timestamp > lastPrescription.timestamp }
        return purchaseLogsAfterPrescription.isEmpty
    }

    func hasEffectivePrescriptionReceived() -> Bool {
        !effectivePrescriptionReceivedLogs().isEmpty
    }

    internal func effectiveLogs(type: LogType, undoType: LogType) -> [LogEntry] {
        guard !logs.isEmpty else { return [] }
        let reversed = reversedOperationIds(for: undoType)
        return logs.filter { log in
            guard log.type == type else { return false }
            guard let opId = log.operationId else { return true }
            return !reversed.contains(opId)
        }
    }

    internal func reversedOperationIds(for undoType: LogType) -> Set<UUID> {
        Set(
            logs.compactMap { log in
                guard log.type == undoType, let opId = log.reversalOfOperationId else { return nil }
                return opId
            }
        )
    }

    var deadlineMonthYear: (month: Int, year: Int)? {
        guard let month = normalizedDeadlineMonth,
              let year = normalizedDeadlineYear else { return nil }
        return (month, year)
    }

    var deadlineLabel: String? {
        guard let info = deadlineMonthYear else { return nil }
        return String(format: "%02d/%04d", info.month, info.year)
    }

    var deadlineMonthStartDate: Date? {
        guard let info = deadlineMonthYear else { return nil }
        var comps = DateComponents()
        comps.year = info.year
        comps.month = info.month
        comps.day = 1
        return Calendar.current.date(from: comps)
    }

    var monthsUntilDeadline: Int? {
        guard let deadlineStart = deadlineMonthStartDate else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return calendar.dateComponents([.month], from: monthStart, to: deadlineStart).month
    }

    internal var normalizedDeadlineMonth: Int? {
        guard let month = deadlineMonth, (1...12).contains(month) else { return nil }
        return month
    }

    internal var normalizedDeadlineYear: Int? {
        let yearRange = 2000...2100
        guard let year = deadlineYear, yearRange.contains(year) else { return nil }
        return year
    }
}

// MARK: - TherapySnapshot extensions

public extension TherapySnapshot {
    var doseAmounts: [Double] {
        doses.map { $0.amount }
    }

    var totalDoseUnitsPerDay: Double {
        let sum = doseAmounts.reduce(0, +)
        return sum > 0 ? sum : 0
    }

    func stimaConsumoGiornaliero(recurrenceService: RecurrencePort) -> Double {
        let rruleString = rrule ?? ""
        if rruleString.isEmpty { return 0 }

        let parsedRule = recurrenceService.parseRecurrenceString(rruleString)
        let freq = parsedRule.freq.uppercased()
        let interval = max(1, parsedRule.interval)
        let byDayCount = parsedRule.byDay.count
        let baseDoseUnits = max(1, totalDoseUnitsPerDay)

        if let on = parsedRule.cycleOnDays,
           let off = parsedRule.cycleOffDays,
           on > 0,
           off > 0,
           freq == "DAILY" {
            let cycleLength = Double(on + off)
            return baseDoseUnits * Double(on) / cycleLength
        }

        switch freq {
        case "DAILY":
            return baseDoseUnits / Double(interval)
        case "WEEKLY":
            let weekly = baseDoseUnits * Double(max(byDayCount, 1))
            return weekly / Double(7 * interval)
        default:
            return 0
        }
    }
}
