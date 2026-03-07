import Foundation
import CoreData

struct DoseEvent {
    let date: Date
    let therapyId: UUID
    let medicineId: UUID
}

struct DoseEventGenerator {
    private enum Strategy {
        case context(TherapyDoseScheduleService)
        case lightweight(RecurrenceManager)
    }

    private let strategy: Strategy
    private let calendar: Calendar

    init(context: NSManagedObjectContext, calendar: Calendar = .current) {
        self.strategy = .context(TherapyDoseScheduleService(context: context, calendar: calendar))
        self.calendar = calendar
    }

    init(calendar: Calendar = .current, recurrenceManager: RecurrenceManager = .shared) {
        self.strategy = .lightweight(recurrenceManager)
        self.calendar = calendar
    }

    func generateEvents(
        therapies: [Therapy],
        from rangeStart: Date,
        to end: Date
    ) -> [DoseEvent] {
        guard !therapies.isEmpty else { return [] }

        let startDay = calendar.startOfDay(for: rangeStart)
        let endDay = calendar.startOfDay(for: end)
        var day = startDay
        var events: [DoseEvent] = []

        while day <= endDay {
            for therapy in therapies {
                let scheduled = effectiveScheduledTimes(on: day, for: therapy)
                guard !scheduled.isEmpty else { continue }
                for date in scheduled {
                    guard date >= rangeStart && date <= end else { continue }
                    events.append(DoseEvent(date: date, therapyId: therapy.id, medicineId: therapy.medicine.id))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return events.sorted { $0.date < $1.date }
    }

    private func effectiveScheduledTimes(on day: Date, for therapy: Therapy) -> [Date] {
        switch strategy {
        case .context(let scheduleService):
            return scheduleService.effectiveScheduledTimes(on: day, for: therapy)
        case .lightweight(let recurrenceManager):
            return lightweightScheduledTimes(on: day, for: therapy, recurrenceManager: recurrenceManager)
        }
    }

    private func lightweightScheduledTimes(
        on day: Date,
        for therapy: Therapy,
        recurrenceManager: RecurrenceManager
    ) -> [Date] {
        let dayStart = calendar.startOfDay(for: day)
        let baseTimes = baseScheduledTimes(on: dayStart, for: therapy, recurrenceManager: recurrenceManager)
        let overrides = (therapy.doseEvents ?? []).filter { event in
            guard let dueAt = event.due_at else { return false }
            return calendar.isDate(dueAt, inSameDayAs: dayStart)
        }

        var timesByBucket = Dictionary(baseTimes.map { (minuteBucket(for: $0), $0) }, uniquingKeysWith: { _, latest in latest })
        for override in overrides {
            guard let dueAt = override.due_at else { continue }
            let bucket = minuteBucket(for: dueAt)
            switch override.statusValue {
            case .planned:
                timesByBucket[bucket] = dueAt
            case .taken, .missed, .skipped:
                timesByBucket.removeValue(forKey: bucket)
            }
        }

        return timesByBucket.values.sorted()
    }

    private func baseScheduledTimes(
        on day: Date,
        for therapy: Therapy,
        recurrenceManager: RecurrenceManager
    ) -> [Date] {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let startDate = therapy.start_date ?? day
        let sortedDoses = (therapy.doses ?? []).sorted { $0.time < $1.time }
        guard !sortedDoses.isEmpty else { return [] }

        let allowed = recurrenceManager.allowedEvents(
            on: day,
            rule: rule,
            startDate: startDate,
            dosesPerDay: max(1, sortedDoses.count),
            calendar: calendar
        )
        guard allowed > 0 else { return [] }

        let limited = sortedDoses.prefix(min(allowed, sortedDoses.count))
        return limited.compactMap { dose in
            guard let combined = combine(day: day, withTime: dose.time) else { return nil }
            return combined >= startDate ? combined : nil
        }
    }

    private func combine(day: Date, withTime time: Date) -> Date? {
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

    private func minuteBucket(for date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }
}
