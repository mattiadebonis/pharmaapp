import Foundation
import CoreData

final class AdherenceDashboardViewModel: ObservableObject {
    @Published var selectedPeriod: AdherencePeriod = .month1
    @Published private(set) var generalSeries: [AdherencePoint] = []
    @Published private(set) var therapies: [TherapySummary] = []
    @Published private(set) var generalTaken: Int = 0
    @Published private(set) var generalPlanned: Int = 0
    @Published private(set) var generalTrendLabel: String = ""

    private let calendar: Calendar
    private let recurrenceManager: RecurrenceManager

    init(
        calendar: Calendar = .current,
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) {
        self.calendar = calendar
        self.recurrenceManager = RecurrenceManager(context: context)
        self.generalTrendLabel = "\(selectedPeriod.trendPrefix): direzione stabile"
    }

    func reload(therapies: [Therapy], logs: [Log]) {
        let period = selectedPeriod
        let endDay = calendar.startOfDay(for: Date())
        let earliestTherapyDate = therapies.compactMap { $0.start_date }.min()
        let earliestLogDate = logs.filter { $0.type == "intake" }.map { $0.timestamp }.min()
        let earliestAvailable = [earliestTherapyDate, earliestLogDate].compactMap { $0 }.min()

        guard let startDay = periodStartDate(
            period: period,
            endDay: endDay,
            earliestAvailable: earliestAvailable
        ) else {
            return
        }

        let days = makeDays(from: startDay, to: endDay)
        let bucketDates = bucketDates(for: days, unit: period.bucketUnit)

        let sortedTherapies = therapies.sorted { lhs, rhs in
            lhs.medicine.nome.localizedCaseInsensitiveCompare(rhs.medicine.nome) == .orderedAscending
        }

        var therapiesByMedicineId: [UUID: [Therapy]] = [:]
        var medicinesById: [UUID: Medicine] = [:]
        for therapy in sortedTherapies {
            let med = therapy.medicine
            medicinesById[med.id] = med
            therapiesByMedicineId[med.id, default: []].append(therapy)
        }

        let logsByMedicineDay = buildLogsIndex(
            medicinesById: medicinesById,
            startDay: startDay,
            endDay: endDay
        )

        var generalBuckets: [Date: CountPair] = [:]
        var therapyBuckets: [UUID: [Date: CountPair]] = [:]
        for therapy in sortedTherapies {
            therapyBuckets[therapy.id] = [:]
        }

        for day in days {
            let bucket = bucketStart(for: day, unit: period.bucketUnit)
            var dayPlanned = 0
            var dayTaken = 0

            for therapy in sortedTherapies {
                let planned = plannedCount(for: therapy, on: day)
                let taken = takenCount(
                    for: therapy,
                    on: day,
                    therapiesByMedicineId: therapiesByMedicineId,
                    logsByMedicineDay: logsByMedicineDay
                )
                dayPlanned += planned
                dayTaken += taken

                var map = therapyBuckets[therapy.id] ?? [:]
                var pair = map[bucket] ?? CountPair()
                pair.planned += planned
                pair.taken += taken
                map[bucket] = pair
                therapyBuckets[therapy.id] = map
            }

            var generalPair = generalBuckets[bucket] ?? CountPair()
            generalPair.planned += dayPlanned
            generalPair.taken += dayTaken
            generalBuckets[bucket] = generalPair
        }

        let series = bucketDates.map { bucket -> AdherencePoint in
            let pair = generalBuckets[bucket] ?? CountPair()
            let value = adherenceValue(taken: pair.taken, planned: pair.planned)
            return AdherencePoint(date: bucket, value: value)
        }

        let totals = generalBuckets.values.reduce(CountPair()) { partial, next in
            CountPair(taken: partial.taken + next.taken, planned: partial.planned + next.planned)
        }

        generalSeries = series
        generalTaken = totals.taken
        generalPlanned = totals.planned

        if totals.planned == 0 {
            generalTrendLabel = "Nessun dato disponibile"
        } else {
            let generalTrend = trendDirection(values: series.map { $0.value })
            generalTrendLabel = "\(period.trendPrefix): \(generalTrend.description)"
        }

        let therapySummaries = sortedTherapies.map { therapy -> TherapySummary in
            let map = therapyBuckets[therapy.id] ?? [:]
            let seriesValues = bucketDates.map { bucket -> Double in
                let pair = map[bucket] ?? CountPair()
                return adherenceValue(taken: pair.taken, planned: pair.planned)
            }

            let totals = map.values.reduce(CountPair()) { partial, next in
                CountPair(taken: partial.taken + next.taken, planned: partial.planned + next.planned)
            }

            let trend = trendDirection(values: seriesValues)
            let statusLabel = trend.statusLabel
            let hasMeasurements = therapy.clinicalRulesValue?.monitoring?.isEmpty == false
            let isSelfReported = therapy.manual_intake_registration
            return TherapySummary(
                id: therapy.id,
                name: therapy.medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Terapia" : therapy.medicine.nome,
                statusLabel: statusLabel,
                taken: totals.taken,
                planned: totals.planned,
                adherenceSeries: seriesValues,
                hasMeasurements: hasMeasurements,
                parameterSeries: nil,
                isSelfReported: isSelfReported
            )
        }

        self.therapies = therapySummaries
    }

    private func makeDays(from start: Date, to end: Date) -> [Date] {
        var days: [Date] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private func periodStartDate(
        period: AdherencePeriod,
        endDay: Date,
        earliestAvailable: Date?
    ) -> Date? {
        switch period {
        case .day1:
            return endDay
        case .week1, .month1:
            if let days = period.totalDays {
                return calendar.date(byAdding: .day, value: -(days - 1), to: endDay)
            }
            return endDay
        case .months6:
            let candidate = calendar.date(byAdding: .month, value: -6, to: endDay)
            return calendar.startOfDay(for: candidate ?? endDay)
        case .all:
            guard let earliest = earliestAvailable else { return endDay }
            return calendar.startOfDay(for: earliest)
        }
    }

    private func bucketDates(for days: [Date], unit: AdherenceBucketUnit) -> [Date] {
        var set = Set<Date>()
        for day in days {
            set.insert(bucketStart(for: day, unit: unit))
        }
        return set.sorted()
    }

    private func bucketStart(for date: Date, unit: AdherenceBucketUnit) -> Date {
        switch unit {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private func plannedCount(for therapy: Therapy, on day: Date) -> Int {
        guard let rrule = therapy.rrule, !rrule.isEmpty else { return 0 }
        let rule = recurrenceManager.parseRecurrenceString(rrule)
        let start = therapy.start_date ?? day
        let dosesPerDay = max(1, therapy.doses?.count ?? 0)
        return recurrenceManager.allowedEvents(
            on: day,
            rule: rule,
            startDate: start,
            dosesPerDay: dosesPerDay,
            calendar: calendar
        )
    }

    private func takenCount(
        for therapy: Therapy,
        on day: Date,
        therapiesByMedicineId: [UUID: [Therapy]],
        logsByMedicineDay: [UUID: [Date: [Log]]]
    ) -> Int {
        let medId = therapy.medicine.id
        guard let logs = logsByMedicineDay[medId]?[day], !logs.isEmpty else { return 0 }
        let assigned = logs.filter { $0.therapy?.objectID == therapy.objectID }.count
        if assigned > 0 { return assigned }

        let unassigned = logs.filter { $0.therapy == nil }
        if unassigned.isEmpty { return 0 }

        let therapyCount = therapiesByMedicineId[medId]?.count ?? 0
        if therapyCount <= 1 { return unassigned.count }
        return unassigned.filter { $0.package?.objectID == therapy.package.objectID }.count
    }

    private func buildLogsIndex(
        medicinesById: [UUID: Medicine],
        startDay: Date,
        endDay: Date
    ) -> [UUID: [Date: [Log]]] {
        var index: [UUID: [Date: [Log]]] = [:]
        for (medId, medicine) in medicinesById {
            let logs = medicine.effectiveIntakeLogs(calendar: calendar)
            guard !logs.isEmpty else { continue }
            for log in logs {
                let day = calendar.startOfDay(for: log.timestamp)
                if day < startDay || day > endDay { continue }
                var dayMap = index[medId] ?? [:]
                var list = dayMap[day] ?? []
                list.append(log)
                dayMap[day] = list
                index[medId] = dayMap
            }
        }
        return index
    }

    private func adherenceValue(taken: Int, planned: Int) -> Double {
        guard planned > 0 else { return 0 }
        return min(1, Double(taken) / Double(planned))
    }
}

private struct CountPair {
    var taken: Int = 0
    var planned: Int = 0
}

private enum TrendDirection {
    case improving
    case stable
    case declining

    var statusLabel: String {
        switch self {
        case .improving: return "In miglioramento"
        case .declining: return "Da supportare"
        case .stable: return "Stabile"
        }
    }

    var description: String {
        switch self {
        case .improving: return "in miglioramento"
        case .declining: return "da supportare"
        case .stable: return "direzione stabile"
        }
    }
}

private func trendDirection(values: [Double]) -> TrendDirection {
    guard values.count >= 2 else { return .stable }
    let mid = values.count / 2
    let first = Array(values.prefix(mid))
    let second = Array(values.suffix(values.count - mid))

    let firstAvg = average(of: first)
    let secondAvg = average(of: second)
    let delta = secondAvg - firstAvg

    if delta > 0.05 { return .improving }
    if delta < -0.05 { return .declining }
    return .stable
}

private func average(of values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sum = values.reduce(0, +)
    return sum / Double(values.count)
}
