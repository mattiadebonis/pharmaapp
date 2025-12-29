import Foundation
import CoreData

func computeSections(for medicines: [Medicine], logs: [Log], option: Option?) -> (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]) {
    let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    let now = Date()
    let cal = Calendar.current
    let endOfDay: Date = {
        let start = cal.startOfDay(for: now)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
    }()

    enum StockStatus {
        case ok
        case low
        case critical
        case unknown
    }

    func remainingUnits(for m: Medicine) -> Int? {
        if let therapies = m.therapies, !therapies.isEmpty {
            return therapies.reduce(0) { $0 + Int($1.leftover()) }
        }
        return m.remainingUnitsWithoutTherapy()
    }

    func nextOccurrence(for m: Medicine) -> Date? {
        guard let therapies = m.therapies, !therapies.isEmpty else { return nil }
        var best: Date? = nil
        for t in therapies {
            let rule = rec.parseRecurrenceString(t.rrule ?? "")
            let startDate = t.start_date ?? now
            if let d = rec.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: t.doses as NSSet?) {
                if best == nil || d < best! { best = d }
            }
        }
        return best
    }

    func icsCode(for date: Date) -> String {
        let weekday = cal.component(.weekday, from: date)
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

    func occursToday(_ t: Therapy) -> Bool {
        let rule = rec.parseRecurrenceString(t.rrule ?? "")
        let start = t.start_date ?? now
        if start > endOfDay { return false }
        if let until = rule.until, cal.startOfDay(for: until) < cal.startOfDay(for: now) { return false }

        let freq = rule.freq.uppercased()
        let interval = rule.interval ?? 1

        switch freq {
        case "DAILY":
            let startSOD = cal.startOfDay(for: start)
            let todaySOD = cal.startOfDay(for: now)
            if let days = cal.dateComponents([.day], from: startSOD, to: todaySOD).day, days >= 0 {
                return days % max(1, interval) == 0
            }
            return false

        case "WEEKLY":
            let todayCode = icsCode(for: now)
            let byDays = rule.byDay.isEmpty ? ["MO","TU","WE","TH","FR","SA","SU"] : rule.byDay
            guard byDays.contains(todayCode) else { return false }

            let startWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
            let todayWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            if let weeks = cal.dateComponents([.weekOfYear], from: startWeek, to: todayWeek).weekOfYear, weeks >= 0 {
                return weeks % max(1, interval) == 0
            }
            return false

        default:
            return false
        }
    }

    func stockStatus(for m: Medicine) -> StockStatus {
        let threshold = m.stockThreshold(option: option)
        if let therapies = m.therapies, !therapies.isEmpty {
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            for therapy in therapies {
                totalLeftover += Double(therapy.leftover())
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: rec)
            }
            if totalDailyUsage <= 0 {
                return totalLeftover > 0 ? .ok : .unknown
            }
            let coverage = totalLeftover / totalDailyUsage
            if coverage <= 0 { return .critical }
            return coverage < Double(threshold) ? .low : .ok
        }
        if let remaining = m.remainingUnitsWithoutTherapy() {
            if remaining <= 0 { return .critical }
            return remaining < threshold ? .low : .ok
        }
        return .unknown
    }

    var purchase: [Medicine] = []
    var oggi: [Medicine] = []
    var ok: [Medicine] = []

    for m in medicines {
        let status = stockStatus(for: m)
        if status == .critical || status == .low {
            purchase.append(m)
            continue
        }
        if let therapies = m.therapies, !therapies.isEmpty, therapies.contains(where: { occursToday($0) }) {
            oggi.append(m)
        } else {
            ok.append(m)
        }
    }

    oggi.sort { (m1, m2) in
        let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
        let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
        if d1 == d2 {
            let r1 = remainingUnits(for: m1) ?? Int.max
            let r2 = remainingUnits(for: m2) ?? Int.max
            if r1 == r2 {
                return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
            }
            return r1 < r2
        }
        return d1 < d2
    }

    purchase.sort { (m1, m2) in
        let s1 = stockStatus(for: m1)
        let s2 = stockStatus(for: m2)
        if s1 != s2 { return (s1 == .critical) && (s2 != .critical) }
        let r1 = remainingUnits(for: m1) ?? Int.max
        let r2 = remainingUnits(for: m2) ?? Int.max
        if r1 == r2 {
            return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
        }
        return r1 < r2
    }

    ok.sort { (m1, m2) in
        let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
        let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
        if d1 == d2 {
            let r1 = remainingUnits(for: m1) ?? Int.max
            let r2 = remainingUnits(for: m2) ?? Int.max
            if r1 == r2 {
                return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
            }
            return r1 < r2
        }
        return d1 < d2
    }

    return (purchase, oggi, ok)
}

func isOutOfStock(_ medicine: Medicine, recurrenceManager: RecurrenceManager) -> Bool {
    if let therapies = medicine.therapies, !therapies.isEmpty {
        var totalLeft: Double = 0
        for therapy in therapies {
            totalLeft += Double(therapy.leftover())
        }
        return totalLeft <= 0
    }
    if let remaining = medicine.remainingUnitsWithoutTherapy() {
        return remaining <= 0
    }
    return false
}

func needsPrescriptionBeforePurchase(_ medicine: Medicine, recurrenceManager: RecurrenceManager) -> Bool {
    guard medicine.obbligo_ricetta else { return false }
    if medicine.hasNewPrescritpionRequest() { return false }

    if let therapies = medicine.therapies, !therapies.isEmpty {
        var totalLeft: Double = 0
        var dailyUsage: Double = 0
        for therapy in therapies {
            totalLeft += Double(therapy.leftover())
            dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        }
        if totalLeft <= 0 { return true }
        guard dailyUsage > 0 else { return false }
        let days = totalLeft / dailyUsage
        let threshold = Double(medicine.stockThreshold(option: nil))
        return days < threshold
    }

    if let remaining = medicine.remainingUnitsWithoutTherapy() {
        return remaining <= medicine.stockThreshold(option: nil)
    }
    return false
}
