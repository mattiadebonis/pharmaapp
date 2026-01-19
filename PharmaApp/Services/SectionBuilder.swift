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

    func deadlineDate(for m: Medicine) -> Date {
        m.deadlineMonthStartDate ?? Date.distantFuture
    }

    func occursToday(_ t: Therapy) -> Bool {
        let rule = rec.parseRecurrenceString(t.rrule ?? "")
        let start = t.start_date ?? now
        let perDay = max(1, t.doses?.count ?? 0)
        let allowed = rec.allowedEvents(
            on: now,
            rule: rule,
            startDate: start,
            dosesPerDay: perDay,
            calendar: cal
        )
        return allowed > 0
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
                let deadline1 = deadlineDate(for: m1)
                let deadline2 = deadlineDate(for: m2)
                if deadline1 != deadline2 {
                    return deadline1 < deadline2
                }
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
            let deadline1 = deadlineDate(for: m1)
            let deadline2 = deadlineDate(for: m2)
            if deadline1 != deadline2 {
                return deadline1 < deadline2
            }
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
                let deadline1 = deadlineDate(for: m1)
                let deadline2 = deadlineDate(for: m2)
                if deadline1 != deadline2 {
                    return deadline1 < deadline2
                }
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
