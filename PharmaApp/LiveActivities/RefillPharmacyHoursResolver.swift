import Foundation

struct RefillPharmacyOpenInfo: Equatable {
    let isOpen: Bool
    let closingTimeText: String?
    let slotText: String?
}

protocol RefillPharmacyHoursResolving {
    func openInfo(forPharmacyName name: String, now: Date) -> RefillPharmacyOpenInfo
}

final class RefillPharmacyHoursResolver: RefillPharmacyHoursResolving {
    private struct PharmacyJSON: Decodable {
        let Nome: String
        let Orari: [DayJSON]?
    }

    private struct DayJSON: Decodable {
        let data: String
        let orario_apertura: String
    }

    private lazy var pharmacies: [PharmacyJSON] = {
        guard let url = Bundle.main.url(forResource: "farmacie", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([PharmacyJSON].self, from: data) else {
            return []
        }
        return list
    }()

    func openInfo(forPharmacyName name: String, now: Date = Date()) -> RefillPharmacyOpenInfo {
        guard let pharmacy = matchPharmacy(named: name),
              let slot = rawTodaySlot(for: pharmacy, now: now) else {
            return RefillPharmacyOpenInfo(isOpen: false, closingTimeText: nil, slotText: nil)
        }

        return Self.openInfo(fromSlot: slot, now: now)
    }

    static func openInfo(fromSlot slot: String, now: Date = Date()) -> RefillPharmacyOpenInfo {
        let intervals = OpeningHoursParser.intervals(from: slot)
        guard !intervals.isEmpty else {
            return RefillPharmacyOpenInfo(isOpen: false, closingTimeText: nil, slotText: slot)
        }

        if let active = OpeningHoursParser.activeInterval(from: slot, now: now) {
            let closing = OpeningHoursParser.timeString(from: active.end)
            return RefillPharmacyOpenInfo(
                isOpen: true,
                closingTimeText: "aperta fino alle \(closing)",
                slotText: slot
            )
        }

        return RefillPharmacyOpenInfo(isOpen: false, closingTimeText: nil, slotText: slot)
    }

    private func rawTodaySlot(for pharmacy: PharmacyJSON, now: Date) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE"
        let weekday = normalize(formatter.string(from: now))

        let dayOrari = pharmacy.Orari?.first(where: { day in
            normalize(day.data).hasPrefix(weekday)
        }) ?? pharmacy.Orari?.first

        return dayOrari?.orario_apertura
    }

    private func matchPharmacy(named name: String) -> PharmacyJSON? {
        let normalizedTarget = normalize(name)
        let targetTokens = tokenize(normalizedTarget)
        guard !targetTokens.isEmpty else { return nil }

        let scored = pharmacies.map { pharmacy -> (PharmacyJSON, Int) in
            let tokens = tokenize(normalize(pharmacy.Nome))
            return (pharmacy, scoreTokens(targetTokens, tokens))
        }

        if let best = scored.max(by: { $0.1 < $1.1 }) {
            let minScore: Int
            if targetTokens.count <= 1 {
                minScore = 1
            } else {
                minScore = max(2, Int(ceil(Double(targetTokens.count) * 0.4)))
            }
            if best.1 >= minScore {
                return best.0
            }
        }

        if targetTokens.count >= 2,
           let direct = pharmacies.first(where: { candidate in
               let normalized = normalize(candidate.Nome)
               return normalized.contains(normalizedTarget) || normalizedTarget.contains(normalized)
           }) {
            return direct
        }

        return nil
    }

    private func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let folded = lowered.folding(options: .diacriticInsensitive, locale: .current)
        let cleaned = folded
            .replacingOccurrences(of: "farmacia", with: "")
            .replacingOccurrences(of: "parafarmacia", with: "")
            .replacingOccurrences(of: "srl", with: "")
            .replacingOccurrences(of: "sas", with: "")
            .replacingOccurrences(of: "snc", with: "")
            .replacingOccurrences(of: "&", with: " ")

        let allowed = cleaned.filter { $0.isLetter || $0.isNumber || $0 == " " }
        return allowed
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenize(_ value: String) -> [String] {
        value.split(separator: " ")
            .map { String($0) }
            .filter { $0.count >= 2 }
    }

    private func scoreTokens(_ target: [String], _ candidate: [String]) -> Int {
        Set(target).intersection(Set(candidate)).count
    }
}
