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
}