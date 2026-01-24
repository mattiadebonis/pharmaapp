import Foundation
import CoreData

struct MedicineAggregateSubtitle {
    let line1: String
    let line2: String
    let chip: String?
}

struct DrawerAggregateSubtitle {
    let line1: String
    let line2: String
}


func makeMedicineSubtitle(
    medicine: Medicine,
    medicinePackage: MedicinePackage? = nil,
    now: Date = Date()
) -> MedicineAggregateSubtitle {
    let context = medicine.managedObjectContext ?? PersistenceController.shared.container.viewContext
    let builder = MedicineSummaryBuilder(context: context)

    if let entry = medicinePackage {
        let entryTherapies = therapies(for: entry)
        let stockUnits = StockService(context: context).units(for: entry.package)
        return builder.build(
            for: entry.medicine,
            therapies: entryTherapies,
            stockUnitsFallback: stockUnits,
            now: now
        )
    }

    return builder.build(for: medicine, now: now)
}

func makeDrawerSubtitle(drawer: Cabinet, now: Date = Date()) -> DrawerAggregateSubtitle {
    let entries = Array(drawer.medicinePackages ?? [])
    let context = drawer.managedObjectContext ?? PersistenceController.shared.container.viewContext
    let recurrenceManager = RecurrenceManager(context: context)

    let todayDoseCount = entries.reduce(0) { total, entry in
        let therapies = therapies(for: entry)
        return total + dosesTodayCount(for: therapies, now: now, recurrenceManager: recurrenceManager)
    }

    var outOfStockCount = 0
    var lowStockCount = 0
    for entry in entries {
        let therapies = therapies(for: entry)
        let threshold = entry.medicine.stockThreshold(option: nil)
        if let days = stockDays(for: entry, therapies: therapies, recurrenceManager: recurrenceManager) {
            if days <= 0 {
                outOfStockCount += 1
            } else if days <= threshold {
                lowStockCount += 1
            }
            continue
        }
        let remaining = StockService(context: context).units(for: entry.package)
        if remaining <= 0 {
            outOfStockCount += 1
        } else if remaining <= threshold {
            lowStockCount += 1
        }
    }

    let line1: String
    if todayDoseCount == 0 {
        line1 = "Nessuna dose oggi"
    } else {
        let doseText = formatCount(todayDoseCount, singular: "dose", plural: "dosi")
        line1 = "Oggi: \(doseText)"
    }

    let line2: String
    if outOfStockCount > 0 {
        let outText = formatCount(outOfStockCount, singular: "finito", plural: "finiti")
        if lowStockCount > 0 {
            let lowText = formatCount(lowStockCount, singular: "scorta bassa", plural: "scorte basse")
            line2 = "\(outText) • \(lowText)"
        } else {
            line2 = outText
        }
    } else if lowStockCount > 0 {
        line2 = formatCount(lowStockCount, singular: "scorta bassa", plural: "scorte basse")
    } else {
        line2 = "Tutto ok"
    }

    return DrawerAggregateSubtitle(line1: line1, line2: line2)
}

private func dosesTodayCount(for therapies: Set<Therapy>, now: Date, recurrenceManager: RecurrenceManager) -> Int {
    guard !therapies.isEmpty else { return 0 }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    var total = 0
    for therapy in therapies {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? today
        let perDay = max(1, therapy.doses?.count ?? 0)
        let allowed = recurrenceManager.allowedEvents(
            on: today,
            rule: rule,
            startDate: start,
            dosesPerDay: perDay,
            calendar: calendar
        )
        total += allowed
    }
    return total
}

private func nextDoseTime(for therapies: Set<Therapy>, now: Date, recurrenceManager: RecurrenceManager) -> Date? {
    guard !therapies.isEmpty else { return nil }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

    let todayTimes = scheduledTimes(for: therapies, on: today, now: now, recurrenceManager: recurrenceManager)
        .filter { $0 > now }
        .sorted()
    if let nextToday = todayTimes.first {
        return nextToday
    }

    let tomorrowTimes = scheduledTimes(for: therapies, on: tomorrow, now: now, recurrenceManager: recurrenceManager)
        .sorted()
    return tomorrowTimes.first
}

private func scheduledTimes(for therapies: Set<Therapy>, on day: Date, now: Date, recurrenceManager: RecurrenceManager) -> [Date] {
    var times: [Date] = []
    for therapy in therapies {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? now
        let perDay = max(1, therapy.doses?.count ?? 0)
        let allowed = recurrenceManager.allowedEvents(
            on: day,
            rule: rule,
            startDate: start,
            dosesPerDay: perDay
        )
        guard allowed > 0 else { continue }
        if let doseSet = therapy.doses, !doseSet.isEmpty {
            let sortedDoses = doseSet.sorted { $0.time < $1.time }
            let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
            times.append(contentsOf: limitedDoses.compactMap { dose in combine(day: day, withTime: dose.time) })
        } else {
            if let next = recurrenceManager.nextOccurrence(rule: rule, startDate: start, after: day, doses: therapy.doses as NSSet?),
               Calendar.current.isDate(next, inSameDayAs: day) {
                times.append(next)
            }
        }
    }
    return times
}

private func frequencyLabel(for therapies: Set<Therapy>, recurrenceManager: RecurrenceManager) -> String? {
    guard let therapy = therapies.first else { return nil }
    let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
    let description = recurrenceManager.describeRecurrence(rule: rule).trimmingCharacters(in: .whitespacesAndNewlines)
    return description.isEmpty ? nil : description
}

private func stockDays(for medicine: Medicine, therapies: Set<Therapy>, recurrenceManager: RecurrenceManager) -> Int? {
    guard !therapies.isEmpty else { return nil }
    var totalLeftover: Double = 0
    var totalDaily: Double = 0
    for therapy in therapies {
        totalLeftover += Double(therapy.leftover())
        totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
    }
    guard totalDaily > 0 else { return nil }
    let days = Int(floor(totalLeftover / totalDaily))
    return max(0, days)
}

private func therapies(for entry: MedicinePackage) -> Set<Therapy> {
    if let set = entry.therapies, !set.isEmpty {
        return set
    }
    let all = entry.medicine.therapies as? Set<Therapy> ?? []
    return Set(all.filter { $0.package == entry.package })
}

private func stockDays(for entry: MedicinePackage, therapies: Set<Therapy>, recurrenceManager: RecurrenceManager) -> Int? {
    guard !therapies.isEmpty else { return nil }
    var totalLeftover: Double = 0
    var totalDaily: Double = 0
    for therapy in therapies {
        totalLeftover += Double(therapy.leftover())
        totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
    }
    guard totalDaily > 0 else { return nil }
    let days = Int(floor(totalLeftover / totalDaily))
    return max(0, days)
}

private func occurs(on day: Date, therapy: Therapy, recurrenceManager: RecurrenceManager) -> Bool {
    let calendar = Calendar.current
    let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
    let start = therapy.start_date ?? day
    let perDay = max(1, therapy.doses?.count ?? 0)
    let allowed = recurrenceManager.allowedEvents(
        on: day,
        rule: rule,
        startDate: start,
        dosesPerDay: perDay,
        calendar: calendar
    )
    return allowed > 0
}

private func combine(day: Date, withTime time: Date) -> Date? {
    let calendar = Calendar.current
    let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)

    var merged = DateComponents()
    merged.year = dayComponents.year
    merged.month = dayComponents.month
    merged.day = dayComponents.day
    merged.hour = timeComponents.hour
    merged.minute = timeComponents.minute
    merged.second = timeComponents.second

    return calendar.date(from: merged)
}

private func formatCount(_ count: Int, singular: String, plural: String) -> String {
    count == 1 ? "1 \(singular)" : "\(count) \(plural)"
}

private func dayLabel(for date: Date) -> String {
    let label = weekdayFormatter.string(from: date).trimmingCharacters(in: .whitespacesAndNewlines)
    return label.isEmpty ? shortDateFormatter.string(from: date) : label
}

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

private let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "it_IT")
    formatter.dateFormat = "EEE"
    return formatter
}()

private let shortDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "it_IT")
    formatter.dateFormat = "dd/MM"
    return formatter
}()
