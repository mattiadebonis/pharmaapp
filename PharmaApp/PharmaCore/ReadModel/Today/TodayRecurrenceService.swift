import Foundation

public struct TodayRecurrenceService {
    public init() {}

    public func parseRecurrenceString(_ icsString: String) -> RecurrenceRule {
        var rule = RecurrenceRule(freq: "DAILY")

        let lines = icsString.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("RRULE:") {
                let rrulePart = trimmed.replacingOccurrences(of: "RRULE:", with: "")
                let components = rrulePart.split(separator: ";")
                for comp in components {
                    let keyVal = comp.split(separator: "=")
                    guard keyVal.count == 2 else { continue }
                    let key = String(keyVal[0])
                    let val = String(keyVal[1])
                    switch key {
                    case "FREQ":
                        rule.freq = val
                    case "INTERVAL":
                        rule.interval = Int(val) ?? 1
                    case "UNTIL":
                        if let date = parseDateUTC(val) { rule.until = date }
                    case "COUNT":
                        rule.count = Int(val)
                    case "BYDAY":
                        rule.byDay = val.split(separator: ",").map { String($0) }
                    case "BYMONTH":
                        rule.byMonth = val.split(separator: ",").compactMap { Int($0) }
                    case "BYMONTHDAY":
                        rule.byMonthDay = val.split(separator: ",").compactMap { Int($0) }
                    case "WKST":
                        rule.wkst = val
                    default:
                        break
                    }
                }
            } else if trimmed.hasPrefix("EXDATE:") {
                let datePart = trimmed.replacingOccurrences(of: "EXDATE:", with: "")
                if let date = parseDateUTC(datePart) { rule.exdates.append(date) }
            } else if trimmed.hasPrefix("RDATE:") {
                let datePart = trimmed.replacingOccurrences(of: "RDATE:", with: "")
                if let date = parseDateUTC(datePart) { rule.rdates.append(date) }
            }
        }

        return rule
    }

    public func allowedEvents(
        on day: Date,
        rule: RecurrenceRule,
        startDate: Date,
        dosesPerDay: Int,
        calendar: Calendar = .current
    ) -> Int {
        let perDay = max(1, dosesPerDay)
        let startDay = calendar.startOfDay(for: startDate)
        let targetDay = calendar.startOfDay(for: day)

        if targetDay < startDay { return 0 }
        if let until = rule.until, calendar.startOfDay(for: until) < targetDay { return 0 }
        guard matchesPattern(day: targetDay, rule: rule, startDate: startDate, calendar: calendar) else {
            return 0
        }

        guard let count = rule.count else { return perDay }
        if count <= 0 { return 0 }

        guard let occurrenceIndex = occurrenceDayIndex(on: targetDay, rule: rule, startDate: startDate, calendar: calendar) else {
            return 0
        }

        let startEventIndex = occurrenceIndex * perDay
        let remaining = count - startEventIndex
        if remaining <= 0 { return 0 }
        return min(perDay, remaining)
    }

    public func nextOccurrence(
        rule: RecurrenceRule,
        startDate: Date,
        after now: Date,
        doses: [DoseSnapshot],
        calendar: Calendar = .current
    ) -> Date? {
        guard !doses.isEmpty else { return nil }

        let sortedDoses = doses.sorted { $0.time < $1.time }
        let freq = rule.freq.uppercased()

        if let countLimit = rule.count {
            guard freq == "DAILY" || freq == "WEEKLY" else { return nil }
            let maxCount = max(0, countLimit)
            guard maxCount > 0 else { return nil }

            var day = calendar.startOfDay(for: startDate)
            var eventIndex = 0

            while eventIndex < maxCount {
                if let until = rule.until, calendar.startOfDay(for: until) < calendar.startOfDay(for: day) {
                    break
                }

                if matchesPattern(day: day, rule: rule, startDate: startDate, calendar: calendar) {
                    for dose in sortedDoses {
                        guard let combinedDate = combine(day: day, withTime: dose.time, calendar: calendar),
                              combinedDate >= startDate else { continue }
                        eventIndex += 1
                        if eventIndex > maxCount { return nil }
                        if combinedDate > now { return combinedDate }
                        if eventIndex >= maxCount { break }
                    }
                }

                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }

            return nil
        }

        let maxOccurrences = 30
        var candidateDates: [Date] = []
        let nowDay = calendar.startOfDay(for: now)

        switch freq {
        case "DAILY":
            let intervalDays = normalizedInterval(rule.interval)
            let startDay = calendar.startOfDay(for: startDate)
            var currentDate = firstAlignedDay(
                startDay: startDay,
                nowDay: nowDay,
                interval: intervalDays,
                calendar: calendar
            )

            for _ in 1...maxOccurrences {
                if let until = rule.until,
                   calendar.startOfDay(for: currentDate) > calendar.startOfDay(for: until) {
                    break
                }
                guard matchesPattern(day: currentDate, rule: rule, startDate: startDate, calendar: calendar) else {
                    currentDate = calendar.date(byAdding: .day, value: intervalDays, to: currentDate) ?? currentDate
                    continue
                }
                for dose in sortedDoses {
                    if let combinedDate = combine(day: currentDate, withTime: dose.time, calendar: calendar),
                       combinedDate >= startDate,
                       combinedDate > now {
                        candidateDates.append(combinedDate)
                    }
                }
                currentDate = calendar.date(byAdding: .day, value: intervalDays, to: currentDate) ?? currentDate
            }

        case "WEEKLY":
            let byDays = rule.byDay.isEmpty ? [weekdayToICS(startDate, calendar: calendar)] : rule.byDay
            let intervalWeeks = normalizedInterval(rule.interval)
            var currentDate = alignedWeekStart(
                startDate: startDate,
                nowDay: nowDay,
                intervalWeeks: intervalWeeks,
                calendar: calendar
            )

            for _ in 1...maxOccurrences {
                if let until = rule.until,
                   calendar.startOfDay(for: currentDate) > calendar.startOfDay(for: until) {
                    break
                }

                var tempDate = currentDate
                for _ in 1...7 {
                    if let until = rule.until,
                       calendar.startOfDay(for: tempDate) > calendar.startOfDay(for: until) {
                        break
                    }
                    let weekdayCode = weekdayToICS(tempDate, calendar: calendar)
                    if byDays.contains(weekdayCode),
                       matchesPattern(day: tempDate, rule: rule, startDate: startDate, calendar: calendar) {
                        for dose in sortedDoses {
                            if let combinedDate = combine(day: tempDate, withTime: dose.time, calendar: calendar),
                               combinedDate >= startDate,
                               combinedDate > now {
                                candidateDates.append(combinedDate)
                            }
                        }
                    }
                    tempDate = calendar.date(byAdding: .day, value: 1, to: tempDate) ?? tempDate
                }

                currentDate = calendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: currentDate) ?? currentDate
            }

        default:
            return nil
        }

        guard !candidateDates.isEmpty else { return nil }
        let nextDate = candidateDates.sorted().first

        if let until = rule.until, let unwrappedNext = nextDate, unwrappedNext > until {
            return nil
        }

        return nextDate
    }

    private func occurrenceDayIndex(
        on day: Date,
        rule: RecurrenceRule,
        startDate: Date,
        calendar: Calendar
    ) -> Int? {
        let startDay = calendar.startOfDay(for: startDate)
        let targetDay = calendar.startOfDay(for: day)
        if targetDay < startDay { return nil }

        var index = 0
        var cursor = startDay
        while cursor <= targetDay {
            if matchesPattern(day: cursor, rule: rule, startDate: startDate, calendar: calendar) {
                if cursor == targetDay { return index }
                index += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return nil
    }

    private func matchesPattern(
        day: Date,
        rule: RecurrenceRule,
        startDate: Date,
        calendar: Calendar
    ) -> Bool {
        let freq = rule.freq.uppercased()
        let interval = normalizedInterval(rule.interval)

        switch freq {
        case "DAILY":
            let startSOD = calendar.startOfDay(for: startDate)
            let daySOD = calendar.startOfDay(for: day)
            if let days = calendar.dateComponents([.day], from: startSOD, to: daySOD).day, days >= 0 {
                return days % interval == 0
            }
            return false

        case "WEEKLY":
            let byDays = rule.byDay.isEmpty ? [weekdayToICS(startDate, calendar: calendar)] : rule.byDay
            guard byDays.contains(weekdayToICS(day, calendar: calendar)) else { return false }

            let startWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)) ?? startDate
            let dayWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)) ?? day
            if let weeks = calendar.dateComponents([.weekOfYear], from: startWeek, to: dayWeek).weekOfYear, weeks >= 0 {
                return weeks % interval == 0
            }
            return false

        default:
            return false
        }
    }

    private func combine(day: Date, withTime time: Date, calendar: Calendar) -> Date? {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)

        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second

        return calendar.date(from: merged)
    }

    private func weekdayToICS(_ date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 1: return "SU"
        case 2: return "MO"
        case 3: return "TU"
        case 4: return "WE"
        case 5: return "TH"
        case 6: return "FR"
        case 7: return "SA"
        default: return "MO"
        }
    }

    private func normalizedInterval(_ interval: Int) -> Int {
        max(1, interval)
    }

    private func firstAlignedDay(
        startDay: Date,
        nowDay: Date,
        interval: Int,
        calendar: Calendar
    ) -> Date {
        if nowDay <= startDay { return startDay }
        let daysSinceStart = calendar.dateComponents([.day], from: startDay, to: nowDay).day ?? 0
        let remainder = daysSinceStart % interval
        if remainder == 0 { return nowDay }
        let daysToAdd = interval - remainder
        return calendar.date(byAdding: .day, value: daysToAdd, to: nowDay) ?? nowDay
    }

    private func alignedWeekStart(
        startDate: Date,
        nowDay: Date,
        intervalWeeks: Int,
        calendar: Calendar
    ) -> Date {
        let startWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate))
            ?? calendar.startOfDay(for: startDate)
        let nowWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nowDay))
            ?? nowDay
        if nowWeek <= startWeek { return startWeek }
        let weeksSinceStart = calendar.dateComponents([.weekOfYear], from: startWeek, to: nowWeek).weekOfYear ?? 0
        let remainder = weeksSinceStart % intervalWeeks
        if remainder == 0 { return nowWeek }
        let weeksToAdd = intervalWeeks - remainder
        return calendar.date(byAdding: .weekOfYear, value: weeksToAdd, to: nowWeek) ?? nowWeek
    }

    private func parseDateUTC(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: dateString)
    }
}
