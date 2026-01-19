import Foundation
import CoreData

struct MedicineSummaryBuilder {
    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private let recurrenceManager: RecurrenceManager

    init(context: NSManagedObjectContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
        self.recurrenceManager = RecurrenceManager(context: context)
    }

    func build(for medicine: Medicine, now: Date = Date()) -> MedicineAggregateSubtitle {
        let therapies = medicine.therapies as? Set<Therapy> ?? []
        let generator = DoseEventGenerator(context: context, calendar: calendar)

        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfToday) ?? now
        let horizonEnd = now.addingTimeInterval(36 * 60 * 60)

        let eventsToday = generator.generateEvents(therapies: Array(therapies), from: startOfToday, to: endOfToday)
        let upcomingEvents = generator.generateEvents(therapies: Array(therapies), from: now, to: horizonEnd)
        let dosesToday = eventsToday.count
        let nextScheduledDose = upcomingEvents.first?.date

        let medicineHasPRN = therapies.contains(where: { $0.manual_intake_registration })
        let hasScheduledToday = dosesToday > 0
        let hasUpcoming = nextScheduledDose != nil
        let hasScheduledWindow = hasScheduledToday || hasUpcoming

        let line1: String
        if hasScheduledToday {
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
        } else if therapies.isEmpty, let remainingUnits = medicine.remainingUnitsWithoutTherapy() {
            let clamped = max(0, remainingUnits)
            let unitsText = formatCount(clamped, singular: "unità", plural: "unità")
            line2 = "Scorte: \(unitsText)"
        } else {
            line2 = "Scorte: —"
        }

        let chip = chipCandidate(
            for: medicine,
            therapies: therapies,
            now: now,
            hasScheduledUpcoming: hasScheduledWindow,
            hasPRN: medicineHasPRN
        )

        return MedicineAggregateSubtitle(line1: line1, line2: line2, chip: chip)
    }

    private func chipCandidate(
        for medicine: Medicine,
        therapies: Set<Therapy>,
        now: Date,
        hasScheduledUpcoming: Bool,
        hasPRN: Bool
    ) -> String? {
        let rules = therapies.compactMap { therapy -> (Therapy, ClinicalRules)? in
            guard let data = therapy.clinicalRules, let decoded = ClinicalRules.decode(from: data) else { return nil }
            return (therapy, decoded)
        }

        if !rules.isEmpty {
            if let courseChip = courseChip(from: rules, now: now) {
                return courseChip
            }
            if rules.contains(where: { ($0.1.taper?.steps.isEmpty == false) }) {
                return "Scala"
            }
            if rules.contains(where: { ($0.1.interactions?.spacing?.isEmpty == false) }) {
                return "Distanza"
            }
            if rules.contains(where: { ($0.1.monitoring?.contains(where: { $0.requiredBeforeDose }) == true) }) {
                return "Misura prima"
            }
        }

        if hasPRN && hasScheduledUpcoming {
            return "PRN"
        }

        return nil
    }

    private func courseChip(from rules: [(Therapy, ClinicalRules)], now: Date) -> String? {
        let candidates = rules.compactMap { pair -> (date: Date, label: String)? in
            let therapy = pair.0
            guard let course = pair.1.course else { return nil }
            guard let startDate = therapy.start_date else { return nil }
            guard course.totalDays > 0 else { return nil }

            let startDay = calendar.startOfDay(for: startDate)
            let today = calendar.startOfDay(for: now)
            let dayIndex = max(1, (calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1)
            let clamped = min(dayIndex, course.totalDays)
            let label = "Giorno \(clamped)/\(course.totalDays)"
            return (startDate, label)
        }

        return candidates.sorted { $0.date < $1.date }.first?.label
    }
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
