import Foundation
import CoreData

private enum SectionStockStatus {
    case ok
    case low
    case critical
    case unknown
}

private struct EntryMetrics {
    let stockStatus: SectionStockStatus
    let remainingUnits: Int?
    let nextOccurrence: Date?
    let occursToday: Bool
    let deadlineDate: Date
    let nameKey: String
}

func computeSections(for medicines: [Medicine], logs: [Log], option: Option?) -> (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]) {
    let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    let now = Date()
    let cal = Calendar.current
    let fallbackContext = medicines.first?.managedObjectContext ?? PersistenceController.shared.container.viewContext
    let stockService = StockService(context: fallbackContext)
    var metricsByID: [NSManagedObjectID: EntryMetrics] = [:]

    for medicine in medicines {
        let therapies = Array(medicine.therapies ?? [])
        let threshold = medicine.stockThreshold(option: option)
        let remainingUnits: Int?
        let nextOccurrence: Date?
        let occursToday: Bool
        let stockStatus: SectionStockStatus

        if therapies.isEmpty {
            if medicine.managedObjectContext != nil {
                remainingUnits = stockService.units(for: medicine)
            } else {
                remainingUnits = medicine.remainingUnitsWithoutTherapy()
            }
            nextOccurrence = nil
            occursToday = false

            if let remaining = remainingUnits {
                if remaining <= 0 {
                    stockStatus = .critical
                } else if remaining < threshold {
                    stockStatus = .low
                } else {
                    stockStatus = .ok
                }
            } else {
                stockStatus = .unknown
            }
        } else {
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            var candidateNext: Date? = nil
            var containsToday = false

            for therapy in therapies {
                let rule = rec.parseRecurrenceString(therapy.rrule ?? "")
                let startDate = therapy.start_date ?? now
                let dosesPerDay = max(1, therapy.doses?.count ?? 0)
                let allowed = rec.allowedEvents(
                    on: now,
                    rule: rule,
                    startDate: startDate,
                    dosesPerDay: dosesPerDay,
                    calendar: cal
                )
                if allowed > 0 {
                    containsToday = true
                }
                if let next = rec.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: therapy.doses as NSSet?) {
                    if let current = candidateNext {
                        candidateNext = min(current, next)
                    } else {
                        candidateNext = next
                    }
                }
                let leftover = Double(therapy.leftover())
                totalLeftover += leftover
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: rec)
            }

            remainingUnits = Int(totalLeftover)
            nextOccurrence = candidateNext
            occursToday = containsToday
            if totalDailyUsage <= 0 {
                stockStatus = totalLeftover > 0 ? .ok : .unknown
            } else {
                let coverage = totalLeftover / totalDailyUsage
                if coverage <= 0 {
                    stockStatus = .critical
                } else if coverage < Double(threshold) {
                    stockStatus = .low
                } else {
                    stockStatus = .ok
                }
            }
        }

        metricsByID[medicine.objectID] = EntryMetrics(
            stockStatus: stockStatus,
            remainingUnits: remainingUnits,
            nextOccurrence: nextOccurrence,
            occursToday: occursToday,
            deadlineDate: medicine.deadlineMonthStartDate ?? Date.distantFuture,
            nameKey: medicine.nome
        )
    }

    func metrics(for medicine: Medicine) -> EntryMetrics {
        metricsByID[medicine.objectID]
            ?? EntryMetrics(
                stockStatus: .unknown,
                remainingUnits: nil,
                nextOccurrence: nil,
                occursToday: false,
                deadlineDate: Date.distantFuture,
                nameKey: medicine.nome
            )
    }

    var purchase: [Medicine] = []
    var oggi: [Medicine] = []
    var ok: [Medicine] = []

    for medicine in medicines {
        let entryMetrics = metrics(for: medicine)
        if entryMetrics.stockStatus == .critical || entryMetrics.stockStatus == .low {
            purchase.append(medicine)
            continue
        }
        if entryMetrics.occursToday {
            oggi.append(medicine)
        } else {
            ok.append(medicine)
        }
    }

    oggi.sort { lhs, rhs in
        let left = metrics(for: lhs)
        let right = metrics(for: rhs)
        let d1 = left.nextOccurrence ?? Date.distantFuture
        let d2 = right.nextOccurrence ?? Date.distantFuture
        if d1 == d2 {
            let r1 = left.remainingUnits ?? Int.max
            let r2 = right.remainingUnits ?? Int.max
            if r1 == r2 {
                if left.deadlineDate != right.deadlineDate {
                    return left.deadlineDate < right.deadlineDate
                }
                return left.nameKey.localizedCaseInsensitiveCompare(right.nameKey) == .orderedAscending
            }
            return r1 < r2
        }
        return d1 < d2
    }

    purchase.sort { lhs, rhs in
        let left = metrics(for: lhs)
        let right = metrics(for: rhs)
        let s1 = left.stockStatus
        let s2 = right.stockStatus
        if s1 != s2 { return (s1 == .critical) && (s2 != .critical) }
        let r1 = left.remainingUnits ?? Int.max
        let r2 = right.remainingUnits ?? Int.max
        if r1 == r2 {
            if left.deadlineDate != right.deadlineDate {
                return left.deadlineDate < right.deadlineDate
            }
            return left.nameKey.localizedCaseInsensitiveCompare(right.nameKey) == .orderedAscending
        }
        return r1 < r2
    }

    ok.sort { lhs, rhs in
        let left = metrics(for: lhs)
        let right = metrics(for: rhs)
        let d1 = left.nextOccurrence ?? Date.distantFuture
        let d2 = right.nextOccurrence ?? Date.distantFuture
        if d1 == d2 {
            let r1 = left.remainingUnits ?? Int.max
            let r2 = right.remainingUnits ?? Int.max
            if r1 == r2 {
                if left.deadlineDate != right.deadlineDate {
                    return left.deadlineDate < right.deadlineDate
                }
                return left.nameKey.localizedCaseInsensitiveCompare(right.nameKey) == .orderedAscending
            }
            return r1 < r2
        }
        return d1 < d2
    }

    return (purchase, oggi, ok)
}

func computeSections(for entries: [MedicinePackage], logs: [Log], option: Option?) -> (purchase: [MedicinePackage], oggi: [MedicinePackage], ok: [MedicinePackage]) {
    let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    let now = Date()
    let cal = Calendar.current
    let stockService = StockService(context: PersistenceController.shared.container.viewContext)
    var metricsByID: [NSManagedObjectID: EntryMetrics] = [:]

    func therapies(for entry: MedicinePackage) -> [Therapy] {
        if let set = entry.therapies, !set.isEmpty {
            return Array(set)
        }
        let all = entry.medicine.therapies as? Set<Therapy> ?? []
        return all.filter { $0.package == entry.package }
    }

    for entry in entries {
        let entryTherapies = therapies(for: entry)
        let threshold = entry.medicine.stockThreshold(option: option)
        let remainingUnits: Int?
        let nextOccurrence: Date?
        let occursToday: Bool
        let stockStatus: SectionStockStatus

        if entryTherapies.isEmpty {
            let remaining = stockService.units(for: entry.package)
            remainingUnits = remaining
            nextOccurrence = nil
            occursToday = false
            if remaining <= 0 {
                stockStatus = .critical
            } else if remaining < threshold {
                stockStatus = .low
            } else {
                stockStatus = .ok
            }
        } else {
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            var candidateNext: Date? = nil
            var containsToday = false
            for therapy in entryTherapies {
                let rule = rec.parseRecurrenceString(therapy.rrule ?? "")
                let start = therapy.start_date ?? now
                let perDay = max(1, therapy.doses?.count ?? 0)
                let allowed = rec.allowedEvents(
                    on: now,
                    rule: rule,
                    startDate: start,
                    dosesPerDay: perDay,
                    calendar: cal
                )
                if allowed > 0 {
                    containsToday = true
                }
                if let next = rec.nextOccurrence(rule: rule, startDate: start, after: now, doses: therapy.doses as NSSet?) {
                    if let current = candidateNext {
                        candidateNext = min(current, next)
                    } else {
                        candidateNext = next
                    }
                }
                totalLeftover += Double(therapy.leftover())
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: rec)
            }

            remainingUnits = Int(totalLeftover)
            nextOccurrence = candidateNext
            occursToday = containsToday
            if totalDailyUsage <= 0 {
                stockStatus = totalLeftover > 0 ? .ok : .unknown
            } else {
                let coverage = totalLeftover / totalDailyUsage
                if coverage <= 0 {
                    stockStatus = .critical
                } else if coverage < Double(threshold) {
                    stockStatus = .low
                } else {
                    stockStatus = .ok
                }
            }
        }

        metricsByID[entry.objectID] = EntryMetrics(
            stockStatus: stockStatus,
            remainingUnits: remainingUnits,
            nextOccurrence: nextOccurrence,
            occursToday: occursToday,
            deadlineDate: Date.distantFuture,
            nameKey: entry.medicine.nome
        )
    }

    func metrics(for entry: MedicinePackage) -> EntryMetrics {
        metricsByID[entry.objectID]
            ?? EntryMetrics(
                stockStatus: .unknown,
                remainingUnits: nil,
                nextOccurrence: nil,
                occursToday: false,
                deadlineDate: Date.distantFuture,
                nameKey: entry.medicine.nome
            )
    }

    var purchase: [MedicinePackage] = []
    var oggi: [MedicinePackage] = []
    var ok: [MedicinePackage] = []

    for entry in entries {
        let entryMetrics = metrics(for: entry)
        if entryMetrics.stockStatus == .critical || entryMetrics.stockStatus == .low {
            purchase.append(entry)
            continue
        }
        if entryMetrics.occursToday {
            oggi.append(entry)
        } else {
            ok.append(entry)
        }
    }

    oggi.sort { lhs, rhs in
        let left = metrics(for: lhs)
        let right = metrics(for: rhs)
        let d1 = left.nextOccurrence ?? Date.distantFuture
        let d2 = right.nextOccurrence ?? Date.distantFuture
        if d1 == d2 {
            let r1 = left.remainingUnits ?? Int.max
            let r2 = right.remainingUnits ?? Int.max
            if r1 == r2 {
                return left.nameKey.localizedCaseInsensitiveCompare(right.nameKey) == .orderedAscending
            }
            return r1 < r2
        }
        return d1 < d2
    }

    purchase.sort { lhs, rhs in
        let left = metrics(for: lhs)
        let right = metrics(for: rhs)
        let s1 = left.stockStatus
        let s2 = right.stockStatus
        if s1 != s2 { return (s1 == .critical) && (s2 != .critical) }
        return left.nameKey.localizedCaseInsensitiveCompare(right.nameKey) == .orderedAscending
    }

    ok.sort { lhs, rhs in
        let left = metrics(for: lhs)
        let right = metrics(for: rhs)
        let r1 = left.remainingUnits ?? Int.max
        let r2 = right.remainingUnits ?? Int.max
        if r1 == r2 {
            return left.nameKey.localizedCaseInsensitiveCompare(right.nameKey) == .orderedAscending
        }
        return r1 < r2
    }

    return (purchase: purchase, oggi: oggi, ok: ok)
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
