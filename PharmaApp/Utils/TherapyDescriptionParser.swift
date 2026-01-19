import Foundation
import CoreData

struct ParsedTherapyDescription {
    struct Dose {
        let amount: Double
        let unit: String
    }

    struct Duration {
        enum Unit {
            case days
            case weeks
            case months
        }

        let value: Int
        let unit: Unit
    }

    enum Frequency {
        case daily(intervalDays: Int)
        case weekly(weekDays: [String])
    }

    var person: Person?
    var dose: Dose?
    var frequency: Frequency?
    var times: [Date]?
    var duration: Duration?
    var requiresConfirmation: Bool?
}

final class TherapyDescriptionParser {
    private let persons: [Person]
    private let defaultPerson: Person?
    private let calendar = Calendar.current

    init(persons: [Person], defaultPerson: Person?) {
        self.persons = persons
        self.defaultPerson = defaultPerson
    }

    func parse(_ raw: String) -> ParsedTherapyDescription {
        let normalized = Self.normalize(raw)

        return ParsedTherapyDescription(
            person: matchPerson(in: normalized),
            dose: parseDose(from: normalized),
            frequency: parseFrequency(from: normalized),
            times: parseTimes(from: normalized),
            duration: parseDuration(from: normalized),
            requiresConfirmation: parseConfirmation(from: normalized)
        )
    }

    // MARK: - Person
    private func matchPerson(in normalized: String) -> Person? {
        if normalized.range(of: #"\bper\s+me\b"#, options: .regularExpression) != nil {
            return defaultPerson ?? persons.first
        }

        for person in persons {
            let fullName = Self.normalize(fullName(for: person))
            if !fullName.isEmpty,
               normalized.range(of: #"\bper\s+\#(NSRegularExpression.escapedPattern(for: fullName))\b"#, options: .regularExpression) != nil {
                return person
            }
            let firstName = Self.normalize((person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            if !firstName.isEmpty,
               normalized.range(of: #"\bper\s+\#(NSRegularExpression.escapedPattern(for: firstName))\b"#, options: .regularExpression) != nil {
                return person
            }
        }

        return nil
    }

    private func fullName(for person: Person) -> String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first
    }

    // MARK: - Dose
    private func parseDose(from normalized: String) -> ParsedTherapyDescription.Dose? {
        // 1) ½ / mezza
        if let match = firstMatch(
            pattern: #"\b(mezza|½|1/2)\s+(compressa|compresse|capsula|capsule)\b"#,
            in: normalized
        ) {
            let unit = canonicalUnit(match[2])
            return .init(amount: 0.5, unit: unit)
        }

        // 2) una compressa
        if let match = firstMatch(
            pattern: #"\buna\s+(compressa|capsula)\b"#,
            in: normalized
        ) {
            let unit = canonicalUnit(match[1])
            return .init(amount: 1, unit: unit)
        }

        // 3) 2 compresse
        if let match = firstMatch(
            pattern: #"\b(\d+(?:[.,]\d+)?)\s+(compressa|compresse|capsula|capsule)\b"#,
            in: normalized
        ) {
            let rawValue = match[1].replacingOccurrences(of: ",", with: ".")
            let value = Double(rawValue) ?? 0
            guard value > 0 else { return nil }
            let unit = canonicalUnit(match[2])
            return .init(amount: value, unit: unit)
        }

        return nil
    }

    private func canonicalUnit(_ raw: String) -> String {
        if raw.hasPrefix("capsul") { return "capsula" }
        return "compressa"
    }

    // MARK: - Frequency
    private func parseFrequency(from normalized: String) -> ParsedTherapyDescription.Frequency? {
        if let days = parseWeekDays(from: normalized), !days.isEmpty {
            return .weekly(weekDays: days)
        }

        if normalized.contains("a giorni alterni") {
            return .daily(intervalDays: 2)
        }

        if let match = firstMatch(pattern: #"\bogni\s+(\d{1,2})\s+giorni\b"#, in: normalized),
           let value = Int(match[1]), value > 0 {
            return .daily(intervalDays: value)
        }

        if normalized.contains("ogni giorno") || normalized.contains("tutti i giorni") || normalized.contains("una volta al giorno") {
            return .daily(intervalDays: 1)
        }

        return nil
    }

    private func parseWeekDays(from normalized: String) -> [String]? {
        let weekOrder = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

        if normalized.contains("weekend") || normalized.contains("fine settimana") {
            return ["SA", "SU"]
        }

        if normalized.range(of: #"\bdal\s+lunedi\s+al\s+venerdi\b"#, options: .regularExpression) != nil {
            return ["MO", "TU", "WE", "TH", "FR"]
        }

        let mapping: [(token: String, code: String)] = [
            ("lunedi", "MO"),
            ("martedi", "TU"),
            ("mercoledi", "WE"),
            ("giovedi", "TH"),
            ("venerdi", "FR"),
            ("sabato", "SA"),
            ("domenica", "SU"),
        ]

        var codes: [String] = []
        for (token, code) in mapping {
            if normalized.range(of: #"\b\#(token)\b"#, options: .regularExpression) != nil {
                codes.append(code)
            }
        }

        let uniqueOrdered = weekOrder.filter { codes.contains($0) }
        return uniqueOrdered.isEmpty ? nil : uniqueOrdered
    }

    // MARK: - Times
    private func parseTimes(from normalized: String) -> [Date]? {
        // alle 8 / alle 08 / alle 08:00 / alle 20:06
        let pattern = #"(?:\balle|\ball')\s*(\d{1,2})(?:[:.](\d{2}))?\b"#
        guard let matches = allMatches(pattern: pattern, in: normalized) else { return nil }

        var seen = Set<String>()
        var result: [(hour: Int, minute: Int)] = []

        for match in matches {
            guard let hour = Int(match[1]), (0...23).contains(hour) else { continue }
            let minute = Int(match[2]) ?? 0
            guard (0...59).contains(minute) else { continue }
            let key = String(format: "%02d:%02d", hour, minute)
            guard seen.insert(key).inserted else { continue }
            result.append((hour: hour, minute: minute))
        }

        guard !result.isEmpty else { return nil }
        result.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }

        let dates: [Date] = result.compactMap { item in
            var comps = DateComponents()
            comps.hour = item.hour
            comps.minute = item.minute
            return calendar.date(from: comps)
        }
        return dates.isEmpty ? nil : dates
    }

    // MARK: - Duration
    private func parseDuration(from normalized: String) -> ParsedTherapyDescription.Duration? {
        let pattern = #"\bper\s+(\d{1,3})\s+(giorni?|settimane?|mesi?)\b"#
        guard let match = firstMatch(pattern: pattern, in: normalized),
              let value = Int(match[1]), value > 0 else { return nil }

        let unitRaw = match[2]
        let unit: ParsedTherapyDescription.Duration.Unit
        if unitRaw.hasPrefix("settim") {
            unit = .weeks
        } else if unitRaw.hasPrefix("mes") {
            unit = .months
        } else {
            unit = .days
        }
        return .init(value: value, unit: unit)
    }

    // MARK: - Confirmation
    private func parseConfirmation(from normalized: String) -> Bool? {
        if normalized.contains("senza conferma") || normalized.contains("no conferma") {
            return false
        }
        if normalized.contains("chiedi conferma") || normalized.contains("con conferma") {
            return true
        }
        return nil
    }

    // MARK: - Regex helpers
    private func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let matches = allMatches(pattern: pattern, in: text), let first = matches.first else { return nil }
        return first
    }

    private func allMatches(pattern: String, in text: String) -> [[String]]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !results.isEmpty else { return nil }

        var all: [[String]] = []
        for r in results {
            var groups: [String] = []
            for i in 0..<r.numberOfRanges {
                let range = r.range(at: i)
                if range.location == NSNotFound {
                    groups.append("")
                } else {
                    groups.append(ns.substring(with: range))
                }
            }
            all.append(groups)
        }
        return all
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
