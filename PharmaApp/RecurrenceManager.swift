//
//  RecurrenceManager.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import Foundation
import CoreData

struct RecurrenceManager {

    let context: NSManagedObjectContext?

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
        
        return rule
    }

    func describeRecurrence(rule: RecurrenceRule) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "it_IT")

        var description = ""

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

        if rule.interval > 1 {
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
    
    private func formatDateUTC(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    private func parseDateUTC(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: dateString)
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
        let sortedDoses = doseSet.sorted { ($0.time ?? Date()) < ($1.time ?? Date()) }
        
        // Se la freq è "DAILY" o "WEEKLY", ci comportiamo in maniera semplificata.
        // Altrimenti, potresti aggiungere ulteriori casi come MONTHLY, YEARLY, etc.
        let freq = rule.freq.uppercased()
        
        // Limitiamoci, per esempio, a generare le prossime 30 occorrenze massime
        // (o i prossimi 30 giorni, se "DAILY") e vediamo quale cade dopo "now".
        
        // Ci aiuta un piccolo enumeratore di date
        let maxOccurrences = 30
        var candidateDates: [Date] = []
        
        var currentDate = startDate
        
        // Se la data di inizio è già nel passato, spostiamoci a "oggi" per non generare date passate
        if currentDate < now {
            currentDate = Calendar.current.startOfDay(for: now)
        }
        
        // Creiamo un calendario per i calcoli
        let calendar = Calendar.current
        
        switch freq {
            
        case "DAILY":
            // Esempio: per i prossimi 30 giorni a partire da currentDate
            for _ in 1...maxOccurrences {
                // Per ogni giorno, aggiungiamo i possibili orari della day
                // Supponendo che 'time' sia NON opzionale: Date (non Date?)
                for dose in sortedDoses {
                    // dose.time è un Date (non faccio if let, non è optional)
                    if let combinedDate = combine(day: currentDate, withTime: dose.time),
                       combinedDate > now {
                        candidateDates.append(combinedDate)
                    }
                }
                // Passiamo al giorno successivo in base all'intervallo
                // Se rule.interval è 2, significa "ogni 2 giorni", etc.
                currentDate = calendar.date(byAdding: .day, value: rule.interval, to: currentDate) ?? currentDate
            }
            
        case "WEEKLY":
            // Esempio semplificato: consideriamo i prossimi 30 "ripetizioni settimanali"
            // Tenendo conto di rule.byDay se vuoi gestire i giorni della settimana
            // (MO, TU, WE, ecc.).
            
            // Se NON hai byDay, assumiamo "tutti i giorni" della settimana,
            // altrimenti usiamo i giorni in byDay.
            let byDays = rule.byDay.isEmpty ? ["MO","TU","WE","TH","FR","SA","SU"] : rule.byDay
            
            for _ in 1...maxOccurrences {
                
                // Cerchiamo la prossima settimana.  
                // Esempio: enumeriamo i 7 giorni della settimana a partire da currentDate
                var tempDate = currentDate
                
                for _ in 1...7 {
                    let weekdayCode = weekdayToICS(tempDate)
                    // Se questo giorno è incluso in byDays
                    if byDays.contains(weekdayCode) {
                        // Aggiungiamo i possibili orari "Dose"
                        // Supponendo che 'time' sia NON opzionale: Date (non Date?)
                        for dose in sortedDoses {
                            // dose.time è un Date (non faccio if let, non è optional)
                            if let combinedDate = combine(day: currentDate, withTime: dose.time),
                               combinedDate > now {
                                candidateDates.append(combinedDate)
                            }
                        }
                    }
                    tempDate = calendar.date(byAdding: .day, value: 1, to: tempDate) ?? tempDate
                }
                
                // Avanziamo di "rule.interval" settimane
                currentDate = calendar.date(byAdding: .day, value: 7 * rule.interval, to: currentDate) ?? currentDate
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
}
