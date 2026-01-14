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

private struct DoseEvent {
    let date: Date
    let isPRN: Bool?
    let therapyID: UUID
}

func makeMedicineSubtitle(medicine: Medicine, now: Date = Date()) -> MedicineAggregateSubtitle {
    let context = medicine.managedObjectContext ?? PersistenceController.shared.container.viewContext
    let recurrenceManager = RecurrenceManager(context: context)
    let therapies = medicine.therapies as? Set<Therapy> ?? []
    let medicineHasPRN = therapies.contains(where: { $0.manual_intake_registration })
    let horizonEnd = now.addingTimeInterval(36 * 60 * 60)
    let events = generateDoseEvents(
        medicine: medicine,
        from: now,
        to: horizonEnd,
        recurrenceManager: recurrenceManager
    )
    let scheduledEvents = events.filter { $0.isPRN != true }
    let hasScheduledUpcoming = !scheduledEvents.isEmpty
    let calendar = Calendar.current
    let dosesToday = scheduledEvents.filter { calendar.isDateInToday($0.date) }.count
    let nextScheduledDose = scheduledEvents.first?.date

    let line1: String
    if hasScheduledUpcoming {
        if dosesToday > 0 {
            let doseText = formatCount(dosesToday, singular: "dose", plural: "dosi")
            if let nextScheduledDose {
                let timeText = timeFormatter.string(from: nextScheduledDose)
                if calendar.isDateInToday(nextScheduledDose) {
                    line1 = "Oggi: \(doseText) • Prossima \(timeText)"
                } else if calendar.isDateInTomorrow(nextScheduledDose) {
                    line1 = "Oggi: \(doseText) • Prossima domani \(timeText)"
                } else {
                    line1 = "Oggi: \(doseText) • Prossima \(timeText)"
                }
            } else {
                line1 = "Oggi: \(doseText)"
            }
        } else if let nextScheduledDose {
            let timeText = timeFormatter.string(from: nextScheduledDose)
            if calendar.isDateInTomorrow(nextScheduledDose) {
                if let frequency = frequencyLabel(for: therapies, recurrenceManager: recurrenceManager) {
                    line1 = "Prossima: domani \(timeText) • \(frequency)"
                } else {
                    line1 = "Prossima: domani \(timeText)"
                }
            } else {
                let dayText = dayLabel(for: nextScheduledDose)
                line1 = "Prossima: \(dayText) \(timeText)"
            }
        } else {
            line1 = "Nessuna dose oggi"
        }
    } else if medicineHasPRN {
        line1 = "Al bisogno (PRN)"
    } else if let frequency = frequencyLabel(for: therapies, recurrenceManager: recurrenceManager) {
        line1 = "Nessuna dose oggi • \(frequency)"
    } else {
        line1 = "Nessuna dose oggi"
    }

    let line2: String
    if let stockDays = stockDays(for: medicine, therapies: therapies, recurrenceManager: recurrenceManager) {
        let threshold = medicine.stockThreshold(option: nil)
        if stockDays <= 0 {
            line2 = "Scorte finite • Compra"
        } else if stockDays <= threshold {
            line2 = "Scorte basse: \(stockDays) gg"
        } else {
            line2 = "Scorte: \(stockDays) gg"
        }
    } else {
        line2 = "Scorte: —"
    }

    let chip: String?
    if medicineHasPRN && hasScheduledUpcoming {
        chip = "PRN"
    } else {
        chip = nil
    }

    return MedicineAggregateSubtitle(line1: line1, line2: line2, chip: chip)
}

func makeDrawerSubtitle(drawer: Cabinet, now: Date = Date()) -> DrawerAggregateSubtitle {
    let medicines = Array(drawer.medicines)
    let context = drawer.managedObjectContext ?? PersistenceController.shared.container.viewContext
    let recurrenceManager = RecurrenceManager(context: context)

    let medCount = medicines.count
    let todayDoseCount = medicines.reduce(0) { total, medicine in
        let therapies = medicine.therapies as? Set<Therapy> ?? []
        return total + dosesTodayCount(for: therapies, now: now, recurrenceManager: recurrenceManager)
    }

    var outOfStockCount = 0
    var lowStockCount = 0
    for medicine in medicines {
        let therapies = medicine.therapies as? Set<Therapy> ?? []
        guard let days = stockDays(for: medicine, therapies: therapies, recurrenceManager: recurrenceManager) else {
            continue
        }
        let threshold = medicine.stockThreshold(option: nil)
        if days <= 0 {
            outOfStockCount += 1
        } else if days <= threshold {
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

private func generateDoseEvents(
    medicine: Medicine,
    from start: Date,
    to end: Date,
    recurrenceManager: RecurrenceManager
) -> [DoseEvent] {
    let therapies = medicine.therapies as? Set<Therapy> ?? []
    guard !therapies.isEmpty else { return [] }
    let calendar = Calendar.current
    let startDay = calendar.startOfDay(for: start)
    let endDay = calendar.startOfDay(for: end)

    var day = startDay
    var events: [DoseEvent] = []
    while day <= endDay {
        for therapy in therapies {
            guard occurs(on: day, therapy: therapy, recurrenceManager: recurrenceManager) else { continue }
            guard let doseSet = therapy.doses, !doseSet.isEmpty else { continue }
            for dose in doseSet {
                guard let date = combine(day: day, withTime: dose.time) else { continue }
                guard date >= start && date <= end else { continue }
                events.append(DoseEvent(date: date, isPRN: nil, therapyID: therapy.id))
            }
        }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = nextDay
    }

    return events.sorted { $0.date < $1.date }
}

private func dosesTodayCount(for therapies: Set<Therapy>, now: Date, recurrenceManager: RecurrenceManager) -> Int {
    guard !therapies.isEmpty else { return 0 }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    var total = 0
    for therapy in therapies {
        guard occurs(on: today, therapy: therapy, recurrenceManager: recurrenceManager) else { continue }
        let doseCount = (therapy.doses?.count ?? 0)
        total += max(1, doseCount)
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
        guard occurs(on: day, therapy: therapy, recurrenceManager: recurrenceManager) else { continue }
        if let doseSet = therapy.doses, !doseSet.isEmpty {
            times.append(contentsOf: doseSet.compactMap { dose in combine(day: day, withTime: dose.time) })
        } else {
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? now
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

private func occurs(on day: Date, therapy: Therapy, recurrenceManager: RecurrenceManager) -> Bool {
    let calendar = Calendar.current
    let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
    let start = therapy.start_date ?? day
    let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: day)) ?? day
    if start > endOfDay { return false }
    if let until = rule.until, calendar.startOfDay(for: until) < calendar.startOfDay(for: day) { return false }

    let freq = rule.freq.uppercased()
    let interval = rule.interval ?? 1

    switch freq {
    case "DAILY":
        let startSOD = calendar.startOfDay(for: start)
        let daySOD = calendar.startOfDay(for: day)
        if let days = calendar.dateComponents([.day], from: startSOD, to: daySOD).day, days >= 0 {
            return days % max(1, interval) == 0
        }
        return false
    case "WEEKLY":
        let weekday = calendar.component(.weekday, from: day)
        let code = icsCode(for: weekday)
        let byDays = rule.byDay.isEmpty ? ["MO","TU","WE","TH","FR","SA","SU"] : rule.byDay
        guard byDays.contains(code) else { return false }
        let startWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
        let dayWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)) ?? day
        if let weeks = calendar.dateComponents([.weekOfYear], from: startWeek, to: dayWeek).weekOfYear, weeks >= 0 {
            return weeks % max(1, interval) == 0
        }
        return false
    default:
        return false
    }
}

private func icsCode(for weekday: Int) -> String {
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
