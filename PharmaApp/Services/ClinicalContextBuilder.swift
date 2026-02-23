import Foundation

public struct ClinicalContext {
    public let monitoring: [TodoItem]
    public let missedDoses: [TodoItem]

    public init(monitoring: [TodoItem], missedDoses: [TodoItem]) {
        self.monitoring = monitoring
        self.missedDoses = missedDoses
    }

    public var allTodos: [TodoItem] {
        monitoring + missedDoses
    }
}

public struct ClinicalContextBuilder {
    private let recurrenceService: PureRecurrenceService
    private let calendar: Calendar
    private let timeFormatter: DateFormatter

    public init(recurrenceService: PureRecurrenceService = PureRecurrenceService(), calendar: Calendar = .current) {
        self.recurrenceService = recurrenceService
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        self.timeFormatter = formatter
    }

    public func build(for medicines: [MedicineSnapshot], now: Date = Date()) -> ClinicalContext {
        let therapies = medicines.flatMap { $0.therapies }
        let generator = SnapshotDoseEventGenerator(recurrenceService: recurrenceService, calendar: calendar)
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfToday) ?? now
        let events = generator.generateEvents(therapies: therapies, from: startOfToday, to: endOfToday)
        let therapiesByID = Dictionary(therapies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let medicinesByID = Dictionary(medicines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let monitoringTodos = buildMonitoringTodos(
            events: events,
            therapiesByID: therapiesByID,
            medicinesByID: medicinesByID,
            now: now,
            startOfToday: startOfToday,
            endOfToday: endOfToday
        )
        let missedDoseTodos = buildMissedDoseTodos(
            events: events,
            therapiesByID: therapiesByID,
            medicinesByID: medicinesByID,
            now: now
        )

        return ClinicalContext(monitoring: monitoringTodos, missedDoses: missedDoseTodos)
    }

    private func buildMonitoringTodos(
        events: [SnapshotDoseEvent],
        therapiesByID: [TherapyId: TherapySnapshot],
        medicinesByID: [MedicineId: MedicineSnapshot],
        now: Date,
        startOfToday: Date,
        endOfToday: Date
    ) -> [TodoItem] {
        var todos: [TodoItem] = []
        for event in events {
            guard let therapy = therapiesByID[event.therapyId] else { continue }
            guard let rules = therapy.clinicalRules else { continue }
            guard let monitoring = rules.monitoring, !monitoring.isEmpty else { continue }

            let medicineName = medicinesByID[event.medicineId]?.name ?? ""
            for action in monitoring where action.schedule == nil {
                let relation = action.resolvedDoseRelation
                let offsetMinutes = action.resolvedOffsetMinutes
                let offsetSeconds = Double(offsetMinutes) * 60
                let triggerDate: Date = {
                    switch relation {
                    case .beforeDose:
                        return event.date.addingTimeInterval(-offsetSeconds)
                    case .afterDose:
                        return event.date.addingTimeInterval(offsetSeconds)
                    }
                }()
                if triggerDate < startOfToday { continue }
                if triggerDate > endOfToday { continue }
                guard triggerDate >= now else { continue }

                let id = "monitoring|dose|\(action.kind.rawValue)|\(relation.rawValue)|\(therapy.externalKey)|\(Int(event.date.timeIntervalSince1970))|\(Int(triggerDate.timeIntervalSince1970))"
                let suffix = relation == .beforeDose ? "prima" : "dopo"
                let detail = "\(relation.label) (\(offsetMinutes) min \(suffix))"
                todos.append(
                    TodoItem(
                        id: id,
                        title: medicineName,
                        detail: detail,
                        category: .monitoring,
                        medicineId: therapy.medicineId
                    )
                )
            }
        }

        let therapies = Array(therapiesByID.values)
        for therapy in therapies {
            guard let rules = therapy.clinicalRules else { continue }
            guard let monitoring = rules.monitoring, !monitoring.isEmpty else { continue }

            let medicineName = medicinesByID[therapy.medicineId]?.name ?? ""
            for action in monitoring {
                guard let schedule = action.schedule else { continue }
                let scheduleEvents = scheduleOccurrences(schedule: schedule, from: startOfToday, to: endOfToday)
                for scheduleDate in scheduleEvents {
                    guard scheduleDate >= now else { continue }
                    let id = "monitoring|schedule|\(action.kind.rawValue)|\(therapy.externalKey)|\(Int(scheduleDate.timeIntervalSince1970))"
                    todos.append(
                        TodoItem(
                            id: id,
                            title: medicineName,
                            detail: nil,
                            category: .monitoring,
                            medicineId: therapy.medicineId
                        )
                    )
                }
            }
        }

        return todos.sorted { lhs, rhs in
            let lhsTime = monitoringTimestamp(from: lhs.id) ?? .distantFuture
            let rhsTime = monitoringTimestamp(from: rhs.id) ?? .distantFuture
            if lhsTime != rhsTime {
                return lhsTime < rhsTime
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func monitoringTimestamp(from id: String) -> Date? {
        let parts = id.split(separator: "|")
        guard let raw = parts.last, let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func buildMissedDoseTodos(
        events: [SnapshotDoseEvent],
        therapiesByID: [TherapyId: TherapySnapshot],
        medicinesByID: [MedicineId: MedicineSnapshot],
        now: Date
    ) -> [TodoItem] {
        let tolerance: TimeInterval = 60 * 60
        var todos: [TodoItem] = []

        for event in events {
            guard event.date < now else { continue }
            guard calendar.isDate(event.date, inSameDayAs: now) else { continue }
            guard let therapy = therapiesByID[event.therapyId] else { continue }
            guard let rules = therapy.clinicalRules else { continue }
            guard let policy = rules.missedDosePolicy, policy != .none else { continue }

            let medicine = medicinesByID[therapy.medicineId]
            if let medicine, hasMatchingIntakeLog(for: event, therapy: therapy, medicine: medicine, tolerance: tolerance) {
                continue
            }

            let timeText = timeFormatter.string(from: event.date)
            let detail = "Dose delle \(timeText) non registrata"
            let id = "missed|\(therapy.externalKey)|\(Int(event.date.timeIntervalSince1970))"
            let medicineName = medicinesByID[event.medicineId]?.name ?? ""
            todos.append(
                TodoItem(
                    id: id,
                    title: medicineName,
                    detail: detail,
                    category: .missedDose,
                    medicineId: therapy.medicineId
                )
            )
        }

        return todos
    }

    private func hasMatchingIntakeLog(
        for event: SnapshotDoseEvent,
        therapy: TherapySnapshot,
        medicine: MedicineSnapshot,
        tolerance: TimeInterval
    ) -> Bool {
        let intakeLogs = medicine.effectiveIntakeLogs()
        guard !intakeLogs.isEmpty else { return false }

        for log in intakeLogs {
            if let logTherapyId = log.therapyId {
                if logTherapyId != therapy.id { continue }
            } else {
                let therapyCount = medicine.therapies.count
                if therapyCount == 1 {
                    // accept the unassigned log
                } else if log.packageId != therapy.packageId {
                    continue
                }
            }

            let delta = abs(log.timestamp.timeIntervalSince(event.date))
            if delta <= tolerance {
                return true
            }
        }

        return false
    }

    private func scheduleOccurrences(
        schedule: MonitoringSchedule,
        from start: Date,
        to end: Date
    ) -> [Date] {
        guard let rrule = schedule.rrule, !rrule.isEmpty else { return [] }
        guard let times = schedule.times, !times.isEmpty else { return [] }

        let rule = recurrenceService.parseRecurrenceString(rrule)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        var day = startDay
        var events: [Date] = []

        while day <= endDay {
            if occurs(on: day, rule: rule, startDate: start) {
                for time in times {
                    if let date = combine(day: day, withTime: time), date >= start && date <= end {
                        events.append(date)
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return events.sorted()
    }

    private func occurs(on day: Date, rule: RecurrenceRule, startDate: Date) -> Bool {
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: day)) ?? day
        if startDate > endOfDay { return false }
        if let until = rule.until, calendar.startOfDay(for: until) < calendar.startOfDay(for: day) { return false }

        let freq = rule.freq.uppercased()
        let interval = max(1, rule.interval)

        switch freq {
        case "DAILY":
            let startSOD = calendar.startOfDay(for: startDate)
            let daySOD = calendar.startOfDay(for: day)
            if let days = calendar.dateComponents([.day], from: startSOD, to: daySOD).day, days >= 0 {
                if let on = rule.cycleOnDays,
                   let off = rule.cycleOffDays,
                   on > 0,
                   off > 0,
                   freq == "DAILY" {
                    let cycleLength = on + off
                    if cycleLength > 0 {
                        let dayIndex = days % cycleLength
                        if dayIndex >= on { return false }
                    }
                }
                return days % interval == 0
            }
            return false
        case "WEEKLY":
            let weekday = calendar.component(.weekday, from: day)
            let code = icsCode(for: weekday)
            let byDays = rule.byDay.isEmpty ? ["MO", "TU", "WE", "TH", "FR", "SA", "SU"] : rule.byDay
            guard byDays.contains(code) else { return false }
            let startWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)) ?? startDate
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
}

private struct SnapshotDoseEvent {
    let date: Date
    let therapyId: TherapyId
    let medicineId: MedicineId
}

private struct SnapshotDoseEventGenerator {
    private let recurrenceService: PureRecurrenceService
    private let calendar: Calendar

    init(recurrenceService: PureRecurrenceService, calendar: Calendar = .current) {
        self.recurrenceService = recurrenceService
        self.calendar = calendar
    }

    func generateEvents(
        therapies: [TherapySnapshot],
        from rangeStart: Date,
        to end: Date
    ) -> [SnapshotDoseEvent] {
        guard !therapies.isEmpty else { return [] }

        let startDay = calendar.startOfDay(for: rangeStart)
        let endDay = calendar.startOfDay(for: end)
        var day = startDay
        var events: [SnapshotDoseEvent] = []

        while day <= endDay {
            for therapy in therapies {
                guard !therapy.doses.isEmpty else { continue }
                guard let rrule = therapy.rrule, !rrule.isEmpty else { continue }
                let rule = recurrenceService.parseRecurrenceString(rrule)
                let therapyStart = therapy.startDate ?? day
                let sortedDoses = therapy.doses.sorted { $0.time < $1.time }
                let perDay = max(1, sortedDoses.count)
                let allowed = recurrenceService.allowedEvents(
                    on: day,
                    rule: rule,
                    startDate: therapyStart,
                    dosesPerDay: perDay,
                    calendar: calendar
                )
                guard allowed > 0 else { continue }

                let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
                for dose in limitedDoses {
                    guard let date = combine(day: day, withTime: dose.time) else { continue }
                    guard date >= therapyStart else { continue }
                    guard date >= rangeStart && date <= end else { continue }
                    events.append(
                        SnapshotDoseEvent(
                            date: date,
                            therapyId: therapy.id,
                            medicineId: therapy.medicineId
                        )
                    )
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return events.sorted { $0.date < $1.date }
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
}
