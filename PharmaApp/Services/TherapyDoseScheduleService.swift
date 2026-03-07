import Foundation
import CoreData

enum MissedDoseNextAction: String, CaseIterable, Identifiable {
    case keepSchedule
    case postponeByStandardInterval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepSchedule:
            return "Lascia la prossima dose com'e"
        case .postponeByStandardInterval:
            return "Posticipa la prossima dose"
        }
    }
}

struct MissedDoseCandidate: Identifiable {
    let therapy: Therapy
    let scheduledAt: Date
    let nextScheduledAt: Date?

    var id: String {
        let bucket = Int(scheduledAt.timeIntervalSince1970 / 60)
        return "\(therapy.id.uuidString)|\(bucket)"
    }
}

final class TherapyDoseScheduleService {
    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private let recurrenceManager: RecurrenceManager
    private let identityProvider: UserIdentityProvider

    init(
        context: NSManagedObjectContext,
        calendar: Calendar = .current,
        identityProvider: UserIdentityProvider = .shared
    ) {
        self.context = context
        self.calendar = calendar
        self.recurrenceManager = RecurrenceManager(context: context)
        self.identityProvider = identityProvider
    }

    func missedDoseCandidate(for medicine: Medicine, package: Package? = nil, now: Date = Date()) -> MissedDoseCandidate? {
        let medicine = inContext(medicine)
        let package = inContextOptional(package)
        let therapies = Array(medicine.therapies ?? []).filter { therapy in
            (therapy.manual_intake_registration || medicine.manual_intake_registration)
                && (package == nil || therapy.package.id == package?.id)
        }
        return missedDoseCandidate(for: therapies, now: now)
    }

    func missedDoseCandidate(for therapies: [Therapy], now: Date = Date()) -> MissedDoseCandidate? {
        var candidates: [MissedDoseCandidate] = []

        for therapy in therapies {
            let pending = pendingScheduledTimes(on: now, for: therapy)
            guard let scheduledAt = pending.first(where: { $0 <= now }) else { continue }
            let nextScheduledAt = nextScheduledTime(for: therapy, after: scheduledAt)
            candidates.append(
                MissedDoseCandidate(
                    therapy: inContext(therapy),
                    scheduledAt: scheduledAt,
                    nextScheduledAt: nextScheduledAt
                )
            )
        }

        return candidates.min { lhs, rhs in
            if lhs.scheduledAt == rhs.scheduledAt {
                return lhs.therapy.medicine.nome.localizedCaseInsensitiveCompare(rhs.therapy.medicine.nome) == .orderedAscending
            }
            return lhs.scheduledAt < rhs.scheduledAt
        }
    }

    func effectiveScheduledTimes(on day: Date, for therapy: Therapy) -> [Date] {
        let therapy = inContext(therapy)
        let dayStart = calendar.startOfDay(for: day)
        let baseTimes = baseScheduledTimes(on: dayStart, for: therapy)
        let overrides = overrideRecords(on: dayStart, for: therapy)

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

    func completedScheduledTimes(on day: Date, for therapy: Therapy) -> [Date] {
        let schedule = effectiveScheduledTimes(on: day, for: therapy)
        guard !schedule.isEmpty else { return [] }

        let explicitBuckets = Set(
            relevantIntakeLogs(on: day, for: therapy)
                .compactMap(\.scheduled_due_at)
                .filter { calendar.isDate($0, inSameDayAs: day) }
                .map(minuteBucket(for:))
        )

        var completedBuckets = explicitBuckets
        var remaining = schedule.filter { !explicitBuckets.contains(minuteBucket(for: $0)) }
        let genericLogs = relevantIntakeLogs(on: day, for: therapy)
            .filter { $0.scheduled_due_at == nil }
            .sorted { $0.timestamp < $1.timestamp }

        for log in genericLogs {
            guard let index = remaining.lastIndex(where: { $0 <= log.timestamp }) else { continue }
            completedBuckets.insert(minuteBucket(for: remaining.remove(at: index)))
        }

        return schedule.filter { completedBuckets.contains(minuteBucket(for: $0)) }
    }

    func pendingScheduledTimes(on day: Date, for therapy: Therapy) -> [Date] {
        let schedule = effectiveScheduledTimes(on: day, for: therapy)
        guard !schedule.isEmpty else { return [] }
        let completedBuckets = Set(completedScheduledTimes(on: day, for: therapy).map(minuteBucket(for:)))
        return schedule.filter { !completedBuckets.contains(minuteBucket(for: $0)) }
    }

    func nextScheduledTime(
        for therapy: Therapy,
        after date: Date,
        maxSearchDays: Int = 60
    ) -> Date? {
        let therapy = inContext(therapy)
        let startDay = calendar.startOfDay(for: date)

        for offset in 0...max(0, maxSearchDays) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let schedule = effectiveScheduledTimes(on: day, for: therapy)
            if let next = schedule.first(where: { $0 > date }) {
                return next
            }
        }

        return nil
    }

    func setOverrideStatus(_ status: DoseEventRecord.Status, for therapy: Therapy, dueAt: Date) {
        let therapy = inContext(therapy)
        let event = existingOverride(for: therapy, dueAt: dueAt) ?? makeOverride(for: therapy, dueAt: dueAt)
        let now = Date()
        event.status = status.rawValue
        event.updated_at = now
        if event.created_at == nil {
            event.created_at = now
        }
        if event.actor_user_id == nil || event.actor_user_id?.isEmpty == true {
            event.actor_user_id = identityProvider.userId
        }
        if event.actor_device_id == nil || event.actor_device_id?.isEmpty == true {
            event.actor_device_id = identityProvider.deviceId
        }
    }

    private func baseScheduledTimes(on day: Date, for therapy: Therapy) -> [Date] {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let startDate = therapy.start_date ?? day
        guard let doses = therapy.doses, !doses.isEmpty else { return [] }

        let sortedDoses = doses.sorted { $0.time < $1.time }
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

    private func relevantIntakeLogs(on day: Date, for therapy: Therapy) -> [Log] {
        let therapy = inContext(therapy)
        let logsOnDay = therapy.medicine.effectiveIntakeLogs(on: day, calendar: calendar)

        let assigned = logsOnDay.filter { $0.therapy?.id == therapy.id }
        let unassigned = logsOnDay.filter { $0.therapy == nil }
        let therapyCount = therapy.medicine.therapies?.count ?? 0
        let packageMatched = therapyCount == 1
            ? unassigned
            : unassigned.filter { $0.package?.id == therapy.package.id }

        var byId: [UUID: Log] = [:]
        for log in assigned + packageMatched {
            byId[log.id] = log
        }
        return byId.values.sorted { $0.timestamp < $1.timestamp }
    }

    private func overrideRecords(on day: Date, for therapy: Therapy) -> [DoseEventRecord] {
        let therapy = inContext(therapy)
        let records = therapy.doseEvents ?? []
        return records.filter { record in
            guard let dueAt = record.due_at else { return false }
            return calendar.isDate(dueAt, inSameDayAs: day)
        }
    }

    private func existingOverride(for therapy: Therapy, dueAt: Date) -> DoseEventRecord? {
        let therapy = inContext(therapy)
        return (therapy.doseEvents ?? []).first { record in
            guard let existingDueAt = record.due_at else { return false }
            return minuteBucket(for: existingDueAt) == minuteBucket(for: dueAt)
        }
    }

    private func makeOverride(for therapy: Therapy, dueAt: Date) -> DoseEventRecord {
        let event = DoseEventRecord(context: context)
        event.id = UUID()
        event.therapy = therapy
        event.medicine = therapy.medicine
        event.due_at = dueAt
        return event
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

    private func inContext<T: NSManagedObject>(_ object: T) -> T {
        if object.managedObjectContext === context {
            return object
        }
        return context.object(with: object.objectID) as! T
    }

    private func inContextOptional<T: NSManagedObject>(_ object: T?) -> T? {
        guard let object else { return nil }
        return inContext(object)
    }
}
