import Foundation

public struct DoseScheduleReadModel {
    private let recurrenceService: RecurrencePort
    private let calendar: Calendar

    public init(recurrenceService: RecurrencePort, calendar: Calendar = .current) {
        self.recurrenceService = recurrenceService
        self.calendar = calendar
    }

    public func baseScheduledTimes(on day: Date, for therapy: TherapySnapshot) -> [Date] {
        let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
        let startDate = therapy.startDate ?? day
        guard !therapy.doses.isEmpty else { return [] }

        let sortedDoses = therapy.doses.sorted { $0.time < $1.time }
        let allowed = recurrenceService.allowedEvents(
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

    public func nextScheduledTime(
        for therapy: TherapySnapshot,
        after date: Date,
        maxSearchDays: Int = 60
    ) -> Date? {
        let startDay = calendar.startOfDay(for: date)

        for offset in 0...max(0, maxSearchDays) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let schedule = baseScheduledTimes(on: day, for: therapy)
            if let next = schedule.first(where: { $0 > date }) {
                return next
            }
        }

        return nil
    }

    public func missedDoseCandidate(
        for therapies: [TherapySnapshot],
        intakeLogs: [LogEntry],
        now: Date
    ) -> (therapyId: TherapyId, scheduledAt: Date, nextScheduledAt: Date?)? {
        var candidates: [(therapyId: TherapyId, scheduledAt: Date, nextScheduledAt: Date?, medicineName: String)]  = []

        for therapy in therapies {
            guard therapy.manualIntakeRegistration else { continue }
            let schedule = baseScheduledTimes(on: now, for: therapy)
            let therapyIntakeLogs = intakeLogs.filter { log in
                log.type == .intake && (log.therapyId == therapy.id || log.therapyId == nil)
            }
            let completedBuckets = completedBuckets(schedule: schedule, intakeLogs: therapyIntakeLogs, on: now)
            let pending = schedule.filter { !completedBuckets.contains(minuteBucket(for: $0)) }

            guard let scheduledAt = pending.first(where: { $0 <= now }) else { continue }
            let nextScheduledAt = nextScheduledTime(for: therapy, after: scheduledAt)
            candidates.append((
                therapyId: therapy.id,
                scheduledAt: scheduledAt,
                nextScheduledAt: nextScheduledAt,
                medicineName: ""
            ))
        }

        guard let best = candidates.min(by: { $0.scheduledAt < $1.scheduledAt }) else { return nil }
        return (therapyId: best.therapyId, scheduledAt: best.scheduledAt, nextScheduledAt: best.nextScheduledAt)
    }

    private func completedBuckets(schedule: [Date], intakeLogs: [LogEntry], on day: Date) -> Set<Int> {
        guard !schedule.isEmpty else { return [] }

        let explicitBuckets = Set(
            intakeLogs
                .compactMap(\.scheduledDueAt)
                .filter { calendar.isDate($0, inSameDayAs: day) }
                .map(minuteBucket(for:))
        )

        var completedBuckets = explicitBuckets
        var remaining = schedule.filter { !explicitBuckets.contains(minuteBucket(for: $0)) }
        let genericLogs = intakeLogs
            .filter { $0.scheduledDueAt == nil }
            .sorted { $0.timestamp < $1.timestamp }

        for log in genericLogs {
            guard let index = remaining.lastIndex(where: { $0 <= log.timestamp }) else { continue }
            completedBuckets.insert(minuteBucket(for: remaining.remove(at: index)))
        }

        return completedBuckets
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
