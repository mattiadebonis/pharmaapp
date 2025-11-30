import Foundation
import CoreData

struct ParsedMedicineInput {
    var remainingText: String
    var units: Int?
    var form: String?
    var customThreshold: Int?
    var doctor: Doctor?
    var needsPrescription: Bool?
    var therapyDraft: TherapyDraft?
    var tokens: [String]
}

struct TherapyDraft {
    var frequency: TherapyFrequency
    var times: [Date]
    var person: Person?
}

enum TherapyFrequency {
    case daily
}

final class MedicineInputParser {
    private let doctors: [Doctor]
    private let persons: [Person]
    private let calendar = Calendar.current
    
    init(doctors: [Doctor], persons: [Person]) {
        self.doctors = doctors
        self.persons = persons
    }
    
    func parse(_ raw: String) -> ParsedMedicineInput {
        var text = raw
        var tokens: [String] = []
        var units: Int?
        var form: String?
        var customThreshold: Int?
        var doctorMatch: Doctor?
        var needsPrescription: Bool?
        var therapyDraft: TherapyDraft?
        
        if let (value, range) = extractThreshold(from: text) {
            customThreshold = value
            needsPrescription = true
            tokens.append("Soglia: \(value)g")
            text = remove(range: range, from: text)
        }
        
        if let (num, frm, range) = extractUnitsForm(from: text) {
            units = num; form = frm
            tokens.append("\(num) \(frm)")
            text = remove(range: range, from: text)
        }
        
        if let (doc, range) = matchDoctor(in: text) {
            doctorMatch = doc
            needsPrescription = true
            tokens.append("Medico: \(doctorFullName(doc))")
            text = remove(range: range, from: text)
        }
        
        if let therapy = extractTherapy(from: text) {
            therapyDraft = therapy
            tokens.append("Terapia: ogni giorno")
            if !therapy.times.isEmpty {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timesString = therapy.times.map { formatter.string(from: $0) }.joined(separator: ", ")
                tokens.append("Orario: \(timesString)")
            }
            if let person = therapy.person {
                tokens.append("Persona: \(personFullName(person))")
            }
        }
        
        let remaining = text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return ParsedMedicineInput(
            remainingText: remaining.isEmpty ? raw : remaining,
            units: units,
            form: form,
            customThreshold: customThreshold,
            doctor: doctorMatch,
            needsPrescription: needsPrescription,
            therapyDraft: therapyDraft,
            tokens: tokens
        )
    }
    
    // MARK: - Extractors
    private func extractThreshold(from text: String) -> (Int, NSRange)? {
        let pattern = #"!(\d{1,3})"#
        return firstIntMatch(pattern: pattern, text: text)
    }
    
    private func extractUnitsForm(from text: String) -> (Int, String, NSRange)? {
        let forms = ["compresse","capsule","fiale","sciroppo","spray","gocce","pz","unità"]
        let pattern = #"(\d{1,4})\s+(\p{L}+)"#
        guard let (match, ranges) = firstMatch(pattern: pattern, text: text) else { return nil }
        let ns = text as NSString
        let word = ns.substring(with: ranges[2]).lowercased()
        guard let matchForm = forms.first(where: { word.hasPrefix($0) }) else { return nil }
        let num = Int(ns.substring(with: ranges[1])) ?? 0
        return (num, matchForm, ranges[0])
    }
    
    private func matchDoctor(in text: String) -> (Doctor, NSRange)? {
        let lower = text.lowercased()
        for doc in doctors {
            let name = doctorFullName(doc).lowercased()
            guard !name.isEmpty, let range = lower.range(of: name) else { continue }
            return (doc, NSRange(range, in: text))
        }
        return nil
    }
    
    private func matchPerson(in text: String) -> (Person, NSRange)? {
        let lower = text.lowercased()
        for person in persons {
            let name = personFullName(person).lowercased()
            guard !name.isEmpty, let range = lower.range(of: name) else { continue }
            return (person, NSRange(range, in: text))
        }
        return nil
    }
    
    private func extractTherapy(from text: String) -> TherapyDraft? {
        let lower = text.lowercased()
        guard lower.contains("ogni giorno") else { return nil }
        var times: [Date] = []
        if let (date, _) = extractTime(from: text) {
            times.append(date)
        }
        let person = matchPerson(in: text)?.0
        return TherapyDraft(frequency: .daily, times: times, person: person)
    }
    
    private func extractTime(from text: String) -> (Date, NSRange)? {
        let pattern = #"alle\s+(\d{1,2}):(\d{2})"#
        guard let (match, ranges) = firstMatch(pattern: pattern, text: text) else { return nil }
        let ns = text as NSString
        let h = Int(ns.substring(with: ranges[1])) ?? 0
        let m = Int(ns.substring(with: ranges[2])) ?? 0
        var comps = DateComponents()
        comps.hour = h; comps.minute = m
        let date = calendar.date(from: comps) ?? Date()
        return (date, ranges[0])
    }
    
    // MARK: - Utilities
    private func firstIntMatch(pattern: String, text: String) -> (Int, NSRange)? {
        guard let (_, ranges) = firstMatch(pattern: pattern, text: text) else { return nil }
        let ns = text as NSString
        let num = Int(ns.substring(with: ranges[1])) ?? 0
        return (num, ranges[0])
    }
    
    private func firstMatch(pattern: String, text: String) -> (NSTextCheckingResult, [NSRange])? {
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let ns = text as NSString
        guard let match = regex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var ranges: [NSRange] = []
        for i in 0..<match.numberOfRanges {
            ranges.append(match.range(at: i))
        }
        return (match, ranges)
    }
    
    private func remove(range: NSRange, from text: String) -> String {
        let ns = NSMutableString(string: text)
        ns.replaceCharacters(in: range, with: " ")
        return ns as String
    }
    
    private func doctorFullName(_ doctor: Doctor) -> String {
        let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (doctor.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [first, last].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
    
    private func personFullName(_ person: Person) -> String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [first, last].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}
