import Foundation
import CoreData

struct TherapyLine: Hashable {
    let prefix: String?
    let description: String
}

struct TherapySummaryBuilder {
    private let recurrenceManager: RecurrenceManager
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    init(recurrenceManager: RecurrenceManager) {
        self.recurrenceManager = recurrenceManager
    }

    /// Summary style matching the Therapy list in MedicineDetailView.
    func summary(for therapy: Therapy) -> String {
        descriptionText(for: therapy, includeTimes: true)
    }

    func line(for therapy: Therapy, now: Date = Date()) -> TherapyLine {
        let description = descriptionText(for: therapy, includeTimes: false)
        let prefix = timePrefix(for: therapy, now: now)
        return TherapyLine(prefix: prefix, description: description)
    }

    private func descriptionText(for therapy: Therapy, includeTimes: Bool) -> String {
        let personName = personDisplayName(for: therapy.person)
        let dose = doseDisplayText(for: therapy)
        let frequency = frequencySummaryText(for: therapy)
        var sentence = "\(dose) \(frequency)"
        if includeTimes, let timesText = timesDescriptionText(for: therapy) {
            sentence += " \(timesText)"
        }
        if let personName, !personName.isEmpty {
            sentence += " per \(personName)"
        }
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    private func personDisplayName(for person: Person?) -> String? {
        guard let person else { return nil }
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? nil : first
    }

    private func doseDisplayText(for therapy: Therapy) -> String {
        let unit = doseUnit(for: therapy)
        if let common = therapy.commonDoseAmount {
            return doseDisplayText(amount: common, unit: unit)
        }
        return "dosi variabili"
    }

    private func doseDisplayText(amount: Double, unit: String) -> String {
        if amount == 0.5 {
            return "\u{00BD} \(unit)"
        }
        let isInt = abs(amount.rounded() - amount) < 0.0001
        let numberString: String = {
            if isInt { return String(Int(amount.rounded())) }
            return String(amount).replacingOccurrences(of: ".", with: ",")
        }()
        let unitString: String = {
            guard amount > 1 else { return unit }
            if unit == "compressa" { return "compresse" }
            if unit == "capsula" { return "capsule" }
            return unit
        }()
        return "\(numberString) \(unitString)"
    }

    private func frequencySummaryText(for therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        switch rule.freq {
        case "DAILY":
            if rule.interval <= 1 { return "al giorno" }
            return "ogni \(rule.interval) giorni"
        case "WEEKLY":
            if !rule.byDay.isEmpty {
                let names = rule.byDay.map { dayCodeToItalian($0) }
                return "nei giorni \(joinedList(names))"
            }
            if rule.interval <= 1 { return "a settimana" }
            return "ogni \(rule.interval) settimane"
        case "MONTHLY":
            if rule.interval <= 1 { return "al mese" }
            return "ogni \(rule.interval) mesi"
        case "YEARLY":
            if rule.interval <= 1 { return "all'anno" }
            return "ogni \(rule.interval) anni"
        default:
            return "a intervalli regolari"
        }
    }

    private func dayCodeToItalian(_ code: String) -> String {
        switch code {
        case "MO": return "luned\u{00EC}"
        case "TU": return "marted\u{00EC}"
        case "WE": return "mercoled\u{00EC}"
        case "TH": return "gioved\u{00EC}"
        case "FR": return "venerd\u{00EC}"
        case "SA": return "sabato"
        case "SU": return "domenica"
        default: return code
        }
    }

    private func joinedList(_ items: [String]) -> String {
        if items.isEmpty { return "" }
        if items.count == 1 { return items[0] }
        if items.count == 2 { return "\(items[0]) e \(items[1])" }
        let prefix = items.dropLast().joined(separator: ", ")
        return "\(prefix) e \(items.last!)"
    }

    private func timesDescriptionText(for therapy: Therapy) -> String? {
        guard let doseSet = therapy.doses as? Set<Dose>, !doseSet.isEmpty else { return nil }
        let includeAmounts = therapy.commonDoseAmount == nil
        let entries = doseSet.sorted { $0.time < $1.time }
        let segments: [String] = entries.map { dose in
            let timeText = Self.timeFormatter.string(from: dose.time)
            if includeAmounts {
                let amountText = doseDisplayText(amount: dose.amountValue, unit: doseUnit(for: therapy))
                return "alle \(timeText) (\(amountText))"
            }
            return "alle \(timeText)"
        }
        guard !segments.isEmpty else { return nil }
        if segments.count == 1 {
            return segments[0]
        }
        if segments.count == 2 {
            return "\(segments[0]) e \(segments[1])"
        }
        let prefixTimes = segments.dropLast().joined(separator: ", ")
        let last = segments.last!
        return "\(prefixTimes) e \(last)"
    }

    private func timePrefix(for therapy: Therapy, now: Date) -> String? {
        let calendar = Calendar.current
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? now
        let next = recurrenceManager.nextOccurrence(rule: rule, startDate: start, after: now, doses: therapy.doses as NSSet?)
        let dayPrefix = next.map { dayPrefixLabel(for: $0, now: now, calendar: calendar) }

        if let doseSet = therapy.doses as? Set<Dose>, !doseSet.isEmpty {
            let times = doseSet.sorted { $0.time < $1.time }
                .map { Self.timeFormatter.string(from: $0.time) }
            let uniqueTimes = Array(NSOrderedSet(array: times)) as? [String] ?? times
            guard !uniqueTimes.isEmpty else { return nil }
            let timeText = uniqueTimes.joined(separator: ", ")
            if let dayPrefix {
                return "\(dayPrefix), \(timeText)"
            }
            return timeText
        }
        if let next {
            let timeText = Self.timeFormatter.string(from: next)
            if let dayPrefix {
                return "\(dayPrefix), \(timeText)"
            }
            return timeText
        }
        return nil
    }

    private func dayPrefixLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "oggi" }
        if calendar.isDateInTomorrow(date) { return "domani" }
        if let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: dayAfterTomorrow) {
            return "dopodomani"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private func doseUnit(for therapy: Therapy) -> String {
        let tipologia = therapy.package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tipologia.contains("capsul") { return "capsula" }
        if tipologia.contains("compress") { return "compressa" }
        let unitFallback = therapy.package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unitFallback.isEmpty { return unitFallback.lowercased() }
        return "unità"
    }
}
