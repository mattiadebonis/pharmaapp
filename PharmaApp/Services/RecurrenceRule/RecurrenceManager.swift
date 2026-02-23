//
//  RecurrenceManager.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import Foundation
import CoreData

struct RecurrenceManager {

    static let shared = RecurrenceManager(context: PersistenceController.shared.container.viewContext)

    let context: NSManagedObjectContext?
    private static let recurrenceCacheQueue = DispatchQueue(label: "RecurrenceManager.parse.cache.queue", attributes: .concurrent)
    private static var recurrenceCache: [String: RecurrenceRule] = [:]
    private static let utcFormatterLock = NSLock()
    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    func buildRecurrenceString(from rule: RecurrenceRule) -> String {
        var lines: [String] = []
        
        var rruleComponents: [String] = []
        
        rruleComponents.append("FREQ=\(rule.freq)")
        
        if rule.interval != 1 {
            rruleComponents.append("INTERVAL=\(rule.interval)")
        }
        
        if let until = rule.until {
            let untilString = formatDateUTC(until)
            rruleComponents.append("UNTIL=\(untilString)")
        }
        
        if let count = rule.count {
            rruleComponents.append("COUNT=\(count)")
        }
        
        if !rule.byDay.isEmpty {
            let byDayString = rule.byDay.joined(separator: ",")
            rruleComponents.append("BYDAY=\(byDayString)")
        }
        
        if !rule.byMonth.isEmpty {
            let byMonthString = rule.byMonth.map { String($0) }.joined(separator: ",")
            rruleComponents.append("BYMONTH=\(byMonthString)")
        }
        
        if !rule.byMonthDay.isEmpty {
            let byMonthDayString = rule.byMonthDay.map { String($0) }.joined(separator: ",")
            rruleComponents.append("BYMONTHDAY=\(byMonthDayString)")
        }

        if rule.freq.uppercased() == "DAILY",
           let onDays = rule.cycleOnDays,
           let offDays = rule.cycleOffDays,
           onDays > 0,
           offDays > 0 {
            rruleComponents.append("X-PHARMAPP-ON=\(onDays)")
            rruleComponents.append("X-PHARMAPP-OFF=\(offDays)")
        }

        if let wkst = rule.wkst {
            rruleComponents.append("WKST=\(wkst)")
        }
        
        let rruleLine = "RRULE:" + rruleComponents.joined(separator: ";")
        lines.append(rruleLine)
        
        for exdate in rule.exdates {
            let exdateString = formatDateUTC(exdate)
            lines.append("EXDATE:\(exdateString)")
        }
        
        for rdate in rule.rdates {
            let rdateString = formatDateUTC(rdate)
            lines.append("RDATE:\(rdateString)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    func parseRecurrenceString(_ icsString: String) -> RecurrenceRule {
        if let cached = Self.cachedRecurrenceRule(for: icsString) {
            return cached
        }

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
                        if let date = parseDateUTC(val) {
                            rule.until = date
                        }
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
                    case "X-PHARMAPP-ON":
                        rule.cycleOnDays = Int(val)
                    case "X-PHARMAPP-OFF":
                        rule.cycleOffDays = Int(val)
                    default:
                        break
                    }
                }
            } else if trimmed.hasPrefix("EXDATE:") {
                let datePart = trimmed.replacingOccurrences(of: "EXDATE:", with: "")
                if let date = parseDateUTC(datePart) {
                    rule.exdates.append(date)
                }
            } else if trimmed.hasPrefix("RDATE:") {
                let datePart = trimmed.replacingOccurrences(of: "RDATE:", with: "")
                if let date = parseDateUTC(datePart) {
                    rule.rdates.append(date)
                }
            }
        }
        
        Self.storeRecurrenceRule(rule, for: icsString)
        return rule
    }

    func describeRecurrence(rule: RecurrenceRule) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "it_IT")

        var description = ""

        if let cycle = normalizedCycle(rule) {
            description += "\(cycle.on) giorni di terapia, \(cycle.off) giorni di pausa"
        } else {
            switch rule.freq {
            case "DAILY":
                description += "ogni giorno"
            case "WEEKLY":
                description += "ogni settimana"
            case "MONTHLY":
                description += "ogni mese"
            case "YEARLY":
                description += "ogni anno"
            default:
                description += "con frequenza non specificata"
            }
        }

        if rule.interval > 1, normalizedCycle(rule) == nil {
            description += " ogni \(rule.interval)"
            switch rule.freq {
            case "DAILY":
                description += " giorni"
            case "WEEKLY":
                description += " settimane"
            case "MONTHLY":
                description += " mesi"
            case "YEARLY":
                description += " anni"
            default:
                break
            }
        }

        if let until = rule.until {
            description += " fino al \(dateFormatter.string(from: until))"
        } else if let count = rule.count {
            description += " per \(count) volte"
        }

        if !rule.byDay.isEmpty {
            let days = rule.byDay.map { dayCodeToItalian($0) }.joined(separator: ", ")
            description += " il \(days)"
        }

        if !rule.byMonth.isEmpty {
            let months = rule.byMonth.map { String($0) }.joined(separator: ", ")
            description += " nei mesi \(months)"
        }

        if !rule.byMonthDay.isEmpty {
            let monthDays = rule.byMonthDay.map { String($0) }.joined(separator: ", ")
            description += " il giorno \(monthDays) del mese"
        }

        if !rule.exdates.isEmpty {
            let exdates = rule.exdates.map { dateFormatter.string(from: $0) }.joined(separator: ", ")
            description += ". Escludendo le date: \(exdates)"
        }

        if !rule.rdates.isEmpty {
            let rdates = rule.rdates.map { dateFormatter.string(from: $0) }.joined(separator: ", ")
            description += ". Includendo date extra: \(rdates)"
        }

        return description
    }

    func allowedEvents(
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
        guard matchesPattern(day: targetDay, rule: rule, startDate: startDate, calendar: calendar) else { return 0 }

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

    /// Convert day codes to Italian day names
    private func dayCodeToItalian(_ code: String) -> String {
        switch code {
        case "MO": return "lunedì"
        case "TU": return "martedì"
        case "WE": return "mercoledì"
        case "TH": return "giovedì"
        case "FR": return "venerdì"
        case "SA": return "sabato"
        case "SU": return "domenica"
        default: return code
        }
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
                if let cycle = normalizedCycle(rule) {
                    let cycleLength = cycle.on + cycle.off
                    if cycleLength > 0 {
                        let dayIndex = days % cycleLength
                        if dayIndex >= cycle.on {
                            return false
                        }
                    }
                }
                return days % interval == 0
            }
            return false

        case "WEEKLY":
            let byDays = rule.byDay.isEmpty ? [weekdayToICS(startDate)] : rule.byDay
            guard byDays.contains(weekdayToICS(day)) else { return false }

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
    
    private func formatDateUTC(_ date: Date) -> String {
        Self.utcFormatterLock.lock()
        defer { Self.utcFormatterLock.unlock() }
        return Self.utcFormatter.string(from: date)
    }
    
    private func parseDateUTC(_ dateString: String) -> Date? {
        Self.utcFormatterLock.lock()
        defer { Self.utcFormatterLock.unlock() }
        return Self.utcFormatter.date(from: dateString)
    }
    // In RecurrenceManager.swift

    func nextOccurrence(
        rule: RecurrenceRule,
        startDate: Date,
        after now: Date,
        doses: NSSet?
    ) -> Date? {
        // Se non ci sono orari (Dose), non sappiamo a che ora assumere
        guard let doseSet = doses as? Set<Dose>, !doseSet.isEmpty else {
            return nil
        }
        
        // Ordiniamo i "Dose" per orario
        let sortedDoses = doseSet.sorted { $0.time < $1.time }
        
        // Se la freq è "DAILY" o "WEEKLY", ci comportiamo in maniera semplificata.
        // Altrimenti, potresti aggiungere ulteriori casi come MONTHLY, YEARLY, etc.
        let freq = rule.freq.uppercased()

        if let countLimit = rule.count {
            let calendar = Calendar.current
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
                        guard let combinedDate = combine(day: day, withTime: dose.time),
                              combinedDate >= startDate else {
                            continue
                        }
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

        // Limitiamoci, per esempio, a generare le prossime 30 occorrenze massime
        // (o i prossimi 30 giorni, se "DAILY") e vediamo quale cade dopo "now".
        
        // Ci aiuta un piccolo enumeratore di date
        let cycleLength = normalizedCycle(rule).map { $0.on + $0.off } ?? 0
        let maxOccurrences = max(30, cycleLength + 1)
        var candidateDates: [Date] = []
        
        // Creiamo un calendario per i calcoli
        let calendar = Calendar.current
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
            // Esempio: per i prossimi 30 giorni a partire da currentDate
            for _ in 1...maxOccurrences {
                if let until = rule.until,
                   calendar.startOfDay(for: currentDate) > calendar.startOfDay(for: until) {
                    break
                }
                guard matchesPattern(day: currentDate, rule: rule, startDate: startDate, calendar: calendar) else {
                    currentDate = calendar.date(byAdding: .day, value: intervalDays, to: currentDate) ?? currentDate
                    continue
                }
                // Per ogni giorno, aggiungiamo i possibili orari della day
                // Supponendo che 'time' sia NON opzionale: Date (non Date?)
                for dose in sortedDoses {
                    // dose.time è un Date (non faccio if let, non è optional)
                    if let combinedDate = combine(day: currentDate, withTime: dose.time),
                       combinedDate >= startDate,
                       combinedDate > now {
                        candidateDates.append(combinedDate)
                    }
                }
                // Passiamo al giorno successivo in base all'intervallo
                // Se rule.interval è 2, significa "ogni 2 giorni", etc.
                currentDate = calendar.date(byAdding: .day, value: intervalDays, to: currentDate) ?? currentDate
            }
            
        case "WEEKLY":
            // Esempio semplificato: consideriamo i prossimi 30 "ripetizioni settimanali"
            // Tenendo conto di rule.byDay se vuoi gestire i giorni della settimana
            // (MO, TU, WE, ecc.).
            
            // Se NON hai byDay, assumiamo "tutti i giorni" della settimana,
            // altrimenti usiamo i giorni in byDay.
            let byDays = rule.byDay.isEmpty ? [weekdayToICS(startDate)] : rule.byDay
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
                
                // Cerchiamo la prossima settimana.  
                // Esempio: enumeriamo i 7 giorni della settimana a partire da currentDate
                var tempDate = currentDate
                
                for _ in 1...7 {
                    if let until = rule.until,
                       calendar.startOfDay(for: tempDate) > calendar.startOfDay(for: until) {
                        break
                    }
                    let weekdayCode = weekdayToICS(tempDate)
                    // Se questo giorno è incluso in byDays
                    if byDays.contains(weekdayCode),
                       matchesPattern(day: tempDate, rule: rule, startDate: startDate, calendar: calendar) {
                        // Aggiungiamo i possibili orari "Dose"
                        // Supponendo che 'time' sia NON opzionale: Date (non Date?)
                        for dose in sortedDoses {
                            // dose.time è un Date (non faccio if let, non è optional)
                            if let combinedDate = combine(day: tempDate, withTime: dose.time),
                               combinedDate >= startDate,
                               combinedDate > now {
                                candidateDates.append(combinedDate)
                            }
                        }
                    }
                    tempDate = calendar.date(byAdding: .day, value: 1, to: tempDate) ?? tempDate
                }
                
                // Avanziamo di "rule.interval" settimane
                currentDate = calendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: currentDate) ?? currentDate
            }
            
        default:
            // Se non gestiamo la freq, restituiamo nil
            print("nextOccurrence - freq \(freq) non gestita")
            return nil
        }
        
        // Se non ci sono date candidate, return nil
        guard !candidateDates.isEmpty else { return nil }
        
        // Ordiniamo le candidate e prendiamo la più vicina
        let nextDate = candidateDates.sorted().first
        
        // Verifichiamo eventuale until (se la regola lo prevede)
        if let until = rule.until, let unwrappedNext = nextDate {
            if unwrappedNext > until {
                return nil
            }
        }
        
        // Verifichiamo eventuale count (se la regola lo prevede),
        // in un'implementazione più completa dovremmo capire quante occorrenze
        // sono già state generate (o consumate) e fermarci se superiamo "count".
        // Per semplicità, non lo implementiamo qui.
        
        return nextDate
    }

    // MARK: - Funzioni di supporto

    /// Combina la parte "giorno" di 'day' con la parte "ora e minuti" di 'time'
    private func combine(day: Date, withTime time: Date) -> Date? {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        
        var mergedComponents = DateComponents()
        mergedComponents.year = dayComponents.year
        mergedComponents.month = dayComponents.month
        mergedComponents.day = dayComponents.day
        mergedComponents.hour = timeComponents.hour
        mergedComponents.minute = timeComponents.minute
        mergedComponents.second = timeComponents.second
        
        return calendar.date(from: mergedComponents)
    }

    /// Converte un Date in un codice weekday ICS (es: "MO", "TU", ...).
    private func weekdayToICS(_ date: Date) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Domenica=1, Lunedì=2, etc. (dipende dal locale, ma in Swift di default Domenica=1)
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

    private func normalizedCycle(_ rule: RecurrenceRule) -> (on: Int, off: Int)? {
        guard let on = rule.cycleOnDays,
              let off = rule.cycleOffDays,
              on > 0,
              off > 0,
              rule.freq.uppercased() == "DAILY" else {
            return nil
        }
        return (on, off)
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

    private static func cachedRecurrenceRule(for raw: String) -> RecurrenceRule? {
        var result: RecurrenceRule?
        recurrenceCacheQueue.sync {
            result = recurrenceCache[raw]
        }
        return result
    }

    private static func storeRecurrenceRule(_ rule: RecurrenceRule, for raw: String) {
        recurrenceCacheQueue.async(flags: .barrier) {
            recurrenceCache[raw] = rule
        }
    }
}
