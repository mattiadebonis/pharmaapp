import Foundation
import CoreData

final class AdherenceDashboardViewModel: ObservableObject {
    @Published private(set) var adherencePercentage: Double = 0
    @Published private(set) var punctualityPercentage: Double = 0
    @Published private(set) var stockCoverageDays: Int = 0
    @Published private(set) var stockCoverageMedicineName: String = ""
    @Published private(set) var stockThreshold: Int = 7
    @Published private(set) var stockSummary: StockSummary = .empty
    @Published private(set) var activeTherapyCount: Int = 0
    @Published private(set) var generalTaken: Int = 0
    @Published private(set) var generalPlanned: Int = 0
    @Published private(set) var weekdayAdherence: [WeekdayAdherence] = []
    @Published private(set) var timeSlotPunctuality: [TimeSlotPunctuality] = []
    @Published private(set) var dayAdherence: [DayAdherence] = []
    @Published private(set) var overallTrend: [OverallTrendPoint] = []
    @Published private(set) var medicineCoverages: [MedicineCoverage] = []
    @Published private(set) var therapyTimeStats: [TherapyTimeStat] = []
    @Published private(set) var earlyRefillCount: Int = 0
    @Published private(set) var earlyRefillTotal: Int = 0
    @Published private(set) var earlyRefillRatio: Double = 0
    @Published private(set) var calmDaysStreak: Int = 0
    @Published private(set) var therapyMonitoringCorrelation: TherapyMonitoringCorrelation?

    private let calendar: Calendar
    private let recurrenceManager: RecurrenceManager
    private let doseEventGenerator: DoseEventGenerator
    private let context: NSManagedObjectContext

    init(
        calendar: Calendar = .current,
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) {
        self.calendar = calendar
        self.context = context
        self.recurrenceManager = RecurrenceManager(context: context)
        self.doseEventGenerator = DoseEventGenerator(context: context, calendar: calendar)
    }

    func reload(therapies: [Therapy], logs: [Log], range: StatisticsRange) {
        let endDay = calendar.startOfDay(for: Date())
        let earliestTherapyDate = therapies.compactMap { $0.start_date }.min()
        let earliestLogDate = logs.filter { $0.type == "intake" }.map { $0.timestamp }.min()
        let earliestAvailable = [earliestTherapyDate, earliestLogDate].compactMap { $0 }.min()

        activeTherapyCount = therapies.filter { !($0.rrule ?? "").isEmpty }.count

        guard let startDay = earliestAvailable.map({ calendar.startOfDay(for: $0) }) else {
            adherencePercentage = 0
            punctualityPercentage = 0
            generalTaken = 0
            generalPlanned = 0
            weekdayAdherence = []
            timeSlotPunctuality = []
            dayAdherence = []
            overallTrend = []
            therapyTimeStats = []
            let coverage = computeStockCoverage()
            stockCoverageDays = coverage.days
            stockCoverageMedicineName = coverage.medicineName
            stockThreshold = coverage.threshold
            stockSummary = coverage.summary
            medicineCoverages = coverage.coverages
            let earlyRefill = computeEarlyRefillCount()
            earlyRefillCount = earlyRefill.early
            earlyRefillTotal = earlyRefill.total
            earlyRefillRatio = earlyRefill.total > 0 ? Double(earlyRefill.early) / Double(earlyRefill.total) : 0
            calmDaysStreak = 0
            therapyMonitoringCorrelation = nil
            return
        }

        let full = computeAdherence(therapies: therapies, logs: logs, startDay: startDay, endDay: endDay)
        generalTaken = full.taken
        generalPlanned = full.planned

        let rangeStartDay = filteredStartDay(for: range, earliestStartDay: startDay, endDay: endDay)
        let filtered = computeAdherence(therapies: therapies, logs: logs, startDay: rangeStartDay, endDay: endDay)
        adherencePercentage = filtered.planned > 0 ? min(1, Double(filtered.taken) / Double(filtered.planned)) : 0
        weekdayAdherence = filtered.weekday
        dayAdherence = filtered.dayByDay

        // Punctuality
        let effectiveLogs = buildEffectiveIntakeLogs(from: logs, startDay: rangeStartDay, endDay: endDay)
        overallTrend = computeOverallTrend(
            therapies: therapies,
            dayAdherence: dayAdherence,
            intakeLogs: effectiveLogs,
            startDay: rangeStartDay,
            endDay: endDay
        )
        punctualityPercentage = computePunctuality(therapies: therapies, intakeLogs: effectiveLogs, startDay: rangeStartDay, endDay: endDay)

        // Punctuality by time slot
        timeSlotPunctuality = computePunctualityByTimeSlot(therapies: therapies, intakeLogs: effectiveLogs, startDay: rangeStartDay, endDay: endDay)

        // Therapy time stats
        therapyTimeStats = computeTherapyTimeStats(effectiveLogs: effectiveLogs, therapies: therapies)

        // Stock coverage
        let coverage = computeStockCoverage()
        stockCoverageDays = coverage.days
        stockCoverageMedicineName = coverage.medicineName
        stockThreshold = coverage.threshold
        stockSummary = coverage.summary
        medicineCoverages = coverage.coverages

        // Early refill count
        let earlyRefill = computeEarlyRefillCount()
        earlyRefillCount = earlyRefill.early
        earlyRefillTotal = earlyRefill.total
        earlyRefillRatio = earlyRefill.total > 0 ? Double(earlyRefill.early) / Double(earlyRefill.total) : 0

        // Calm days streak (consecutive days from today):
        // - no stockouts (all monitored medicines have days > 0)
        // - perfect daily adherence (or no planned doses on that day)
        calmDaysStreak = computeCalmDaysStreak(dayAdherence: dayAdherence, coverages: medicineCoverages)

        // Correlation between monitored parameter and therapy adherence
        therapyMonitoringCorrelation = computeTherapyMonitoringCorrelation(
            therapies: therapies,
            startDay: rangeStartDay,
            endDay: endDay
        )
    }

    // MARK: - Adherence

    private func computeAdherence(therapies: [Therapy], logs: [Log], startDay: Date, endDay: Date) -> (taken: Int, planned: Int, weekday: [WeekdayAdherence], dayByDay: [DayAdherence]) {
        let days = makeDays(from: startDay, to: endDay)

        var therapiesByMedicineId: [UUID: [Therapy]] = [:]
        var medicinesById: [UUID: Medicine] = [:]
        for therapy in therapies {
            let med = therapy.medicine
            medicinesById[med.id] = med
            therapiesByMedicineId[med.id, default: []].append(therapy)
        }

        let logsByMedicineDay = buildLogsIndex(medicinesById: medicinesById, startDay: startDay, endDay: endDay)

        var totalPlanned = 0
        var totalTaken = 0
        var dayByDay: [DayAdherence] = []

        // weekday index 1=Sun, 2=Mon, ..., 7=Sat in Calendar
        var weekdayTaken = [Int: Int]()
        var weekdayPlanned = [Int: Int]()

        for day in days {
            let wd = calendar.component(.weekday, from: day)
            var dayPlanned = 0
            var dayTaken = 0

            for therapy in therapies {
                let planned = plannedCount(for: therapy, on: day)
                let taken = takenCount(
                    for: therapy,
                    on: day,
                    therapiesByMedicineId: therapiesByMedicineId,
                    logsByMedicineDay: logsByMedicineDay
                )
                dayPlanned += planned
                dayTaken += taken
            }

            totalPlanned += dayPlanned
            totalTaken += dayTaken
            weekdayPlanned[wd, default: 0] += dayPlanned
            weekdayTaken[wd, default: 0] += dayTaken
            dayByDay.append(DayAdherence(date: day, taken: dayTaken, planned: dayPlanned))
        }

        // Build ordered Mon→Sun (weekday 2,3,4,5,6,7,1)
        let labels = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
        let order = [2, 3, 4, 5, 6, 7, 1]
        var weekday: [WeekdayAdherence] = []
        for (i, wd) in order.enumerated() {
            let p = weekdayPlanned[wd] ?? 0
            let t = weekdayTaken[wd] ?? 0
            let pct = p > 0 ? min(1, Double(t) / Double(p)) : 0
            weekday.append(WeekdayAdherence(label: labels[i], percentage: pct))
        }

        return (totalTaken, totalPlanned, weekday, dayByDay)
    }

    // MARK: - Punctuality

    private func computePunctuality(therapies: [Therapy], intakeLogs: [Log], startDay: Date, endDay: Date) -> Double {
        guard !intakeLogs.isEmpty else { return 0 }

        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDay) else { return 0 }
        let events = doseEventGenerator.generateEvents(therapies: therapies, from: startDay, to: rangeEnd)
        guard !events.isEmpty else { return 0 }

        struct DayMedicineKey: Hashable {
            let day: Date
            let medicineId: NSManagedObjectID
        }

        var eventsByKey: [DayMedicineKey: [DoseEvent]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            let key = DayMedicineKey(day: day, medicineId: event.medicineId)
            eventsByKey[key, default: []].append(event)
        }

        var usedIndices: [DayMedicineKey: Set<Int>] = [:]
        var onTimeCount = 0
        var matchedCount = 0
        let tolerance: TimeInterval = 30 * 60

        for log in intakeLogs {
            let day = calendar.startOfDay(for: log.timestamp)
            let key = DayMedicineKey(day: day, medicineId: log.medicine.objectID)

            guard let candidates = eventsByKey[key], !candidates.isEmpty else { continue }

            var used = usedIndices[key] ?? []
            var bestIndex: Int?
            var bestDelta: TimeInterval = .greatestFiniteMagnitude

            for (i, event) in candidates.enumerated() {
                if used.contains(i) { continue }
                let delta = abs(log.timestamp.timeIntervalSince(event.date))
                if delta < bestDelta {
                    bestDelta = delta
                    bestIndex = i
                }
            }

            guard let idx = bestIndex else { continue }
            used.insert(idx)
            usedIndices[key] = used
            matchedCount += 1
            if bestDelta <= tolerance {
                onTimeCount += 1
            }
        }

        return matchedCount > 0 ? Double(onTimeCount) / Double(matchedCount) : 0
    }

    private func computeOverallTrend(
        therapies: [Therapy],
        dayAdherence: [DayAdherence],
        intakeLogs: [Log],
        startDay: Date,
        endDay: Date
    ) -> [OverallTrendPoint] {
        let punctualityByDay = computeDailyPunctualityByDay(
            therapies: therapies,
            intakeLogs: intakeLogs,
            startDay: startDay,
            endDay: endDay
        )
        let adherenceByDay = Dictionary(
            uniqueKeysWithValues: dayAdherence.map { (calendar.startOfDay(for: $0.date), $0.percentage) }
        )

        return makeDays(from: startDay, to: endDay).map { day in
            OverallTrendPoint(
                date: day,
                adherence: adherenceByDay[day] ?? -1,
                punctuality: punctualityByDay[day] ?? -1
            )
        }
    }

    private func computeDailyPunctualityByDay(
        therapies: [Therapy],
        intakeLogs: [Log],
        startDay: Date,
        endDay: Date
    ) -> [Date: Double] {
        guard !intakeLogs.isEmpty else { return [:] }
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDay) else { return [:] }
        let events = doseEventGenerator.generateEvents(therapies: therapies, from: startDay, to: rangeEnd)
        guard !events.isEmpty else { return [:] }

        struct DayMedicineKey: Hashable {
            let day: Date
            let medicineId: NSManagedObjectID
        }

        var eventsByKey: [DayMedicineKey: [DoseEvent]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            let key = DayMedicineKey(day: day, medicineId: event.medicineId)
            eventsByKey[key, default: []].append(event)
        }

        var usedIndices: [DayMedicineKey: Set<Int>] = [:]
        var matchedByDay: [Date: Int] = [:]
        var onTimeByDay: [Date: Int] = [:]
        let tolerance: TimeInterval = 30 * 60

        for log in intakeLogs {
            let day = calendar.startOfDay(for: log.timestamp)
            let key = DayMedicineKey(day: day, medicineId: log.medicine.objectID)
            guard let candidates = eventsByKey[key], !candidates.isEmpty else { continue }

            var used = usedIndices[key] ?? []
            var bestIndex: Int?
            var bestDelta: TimeInterval = .greatestFiniteMagnitude

            for (i, event) in candidates.enumerated() {
                if used.contains(i) { continue }
                let delta = abs(log.timestamp.timeIntervalSince(event.date))
                if delta < bestDelta {
                    bestDelta = delta
                    bestIndex = i
                }
            }

            guard let idx = bestIndex else { continue }
            used.insert(idx)
            usedIndices[key] = used
            matchedByDay[day, default: 0] += 1
            if bestDelta <= tolerance {
                onTimeByDay[day, default: 0] += 1
            }
        }

        var result: [Date: Double] = [:]
        for (day, matched) in matchedByDay {
            guard matched > 0 else { continue }
            let onTime = onTimeByDay[day, default: 0]
            result[day] = Double(onTime) / Double(matched)
        }
        return result
    }

    private func computePunctualityByTimeSlot(therapies: [Therapy], intakeLogs: [Log], startDay: Date, endDay: Date) -> [TimeSlotPunctuality] {
        guard !intakeLogs.isEmpty else { return [] }
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDay) else { return [] }
        let events = doseEventGenerator.generateEvents(therapies: therapies, from: startDay, to: rangeEnd)
        guard !events.isEmpty else { return [] }

        struct DayMedicineKey: Hashable {
            let day: Date
            let medicineId: NSManagedObjectID
        }

        var eventsByKey: [DayMedicineKey: [DoseEvent]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            let key = DayMedicineKey(day: day, medicineId: event.medicineId)
            eventsByKey[key, default: []].append(event)
        }

        let slotLabels = ["Mattina", "Pomeriggio", "Sera", "Notte"]
        var slotOnTime = [0, 0, 0, 0]
        var slotMatched = [0, 0, 0, 0]

        var usedIndices: [DayMedicineKey: Set<Int>] = [:]
        let tolerance: TimeInterval = 30 * 60

        for log in intakeLogs {
            let day = calendar.startOfDay(for: log.timestamp)
            let key = DayMedicineKey(day: day, medicineId: log.medicine.objectID)
            guard let candidates = eventsByKey[key], !candidates.isEmpty else { continue }

            var used = usedIndices[key] ?? []
            var bestIndex: Int?
            var bestDelta: TimeInterval = .greatestFiniteMagnitude

            for (i, event) in candidates.enumerated() {
                if used.contains(i) { continue }
                let delta = abs(log.timestamp.timeIntervalSince(event.date))
                if delta < bestDelta {
                    bestDelta = delta
                    bestIndex = i
                }
            }

            guard let idx = bestIndex else { continue }
            used.insert(idx)
            usedIndices[key] = used

            let scheduledHour = calendar.component(.hour, from: candidates[idx].date)
            let slotIndex = timeSlotIndex(for: scheduledHour)

            slotMatched[slotIndex] += 1
            if bestDelta <= tolerance {
                slotOnTime[slotIndex] += 1
            }
        }

        var result: [TimeSlotPunctuality] = []
        for i in 0..<4 {
            guard slotMatched[i] > 0 else { continue }
            let pct = Double(slotOnTime[i]) / Double(slotMatched[i])
            result.append(TimeSlotPunctuality(label: slotLabels[i], percentage: pct))
        }
        return result
    }

    private func timeSlotIndex(for hour: Int) -> Int {
        switch hour {
        case 6..<12: return 0
        case 12..<18: return 1
        case 18..<22: return 2
        default: return 3
        }
    }

    private func buildEffectiveIntakeLogs(from logs: [Log], startDay: Date, endDay: Date) -> [Log] {
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDay) else { return [] }
        let undoOperationIds = Set(
            logs.filter { $0.type == "intake_undo" }
                .compactMap { $0.reversal_of_operation_id }
        )
        return logs.filter { log in
            log.type == "intake"
            && log.timestamp >= startDay
            && log.timestamp < rangeEnd
            && !undoOperationIds.contains(log.operation_id ?? UUID())
        }
    }

    // MARK: - Therapy Time Stats

    private func computeTherapyTimeStats(effectiveLogs: [Log], therapies: [Therapy]) -> [TherapyTimeStat] {
        var logsByMed: [NSManagedObjectID: [Double]] = [:]
        for log in effectiveLogs {
            let c = calendar.dateComponents([.hour, .minute], from: log.timestamp)
            let minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            logsByMed[log.medicine.objectID, default: []].append(minutes)
        }

        var stats: [TherapyTimeStat] = []
        var seen = Set<NSManagedObjectID>()
        for therapy in therapies {
            let medID = therapy.medicine.objectID
            guard seen.insert(medID).inserted else { continue }
            guard let times = logsByMed[medID], times.count >= 2 else { continue }
            let avg = times.reduce(0, +) / Double(times.count)
            let variance = times.map { pow($0 - avg, 2) }.reduce(0, +) / Double(times.count)
            let stdDev = Int(sqrt(variance).rounded())
            stats.append(TherapyTimeStat(
                medicineName: therapy.medicine.nome,
                avgHour: Int(avg) / 60,
                avgMinute: Int(avg) % 60,
                stdDevMinutes: stdDev
            ))
        }
        return stats.sorted { $0.medicineName < $1.medicineName }
    }

    // MARK: - Stock Coverage

    private func computeStockCoverage() -> (days: Int, medicineName: String, threshold: Int, summary: StockSummary, coverages: [MedicineCoverage]) {
        let request = Medicine.extractMedicines()
        let medicines: [Medicine]
        do {
            medicines = try context.fetch(request)
        } catch {
            return (0, "", 7, .empty, [])
        }

        var minCoverage = Int.max
        var minMedicineName = ""
        var minThreshold = 7
        var totalCount = 0
        var okCount = 0
        var notOkDays: [Int] = []
        var coverages: [MedicineCoverage] = []

        for medicine in medicines {
            guard let therapies = medicine.therapies, !therapies.isEmpty else { continue }

            var totaleScorte: Double = 0
            var consumoGiornalieroTotale: Double = 0

            for therapy in therapies {
                totaleScorte += Double(therapy.leftover())
                consumoGiornalieroTotale += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }

            guard consumoGiornalieroTotale > 0 else { continue }

            let coverageDays = Int(floor(totaleScorte / consumoGiornalieroTotale))
            let threshold = medicine.stockThreshold(option: nil)

            coverages.append(MedicineCoverage(name: medicine.nome, days: coverageDays, threshold: threshold))

            totalCount += 1
            if coverageDays >= threshold {
                okCount += 1
            } else {
                notOkDays.append(coverageDays)
            }

            if coverageDays < minCoverage {
                minCoverage = coverageDays
                minMedicineName = medicine.nome
                minThreshold = threshold
            }
        }

        coverages.sort { $0.days < $1.days }

        let summary = StockSummary(
            totalCount: totalCount,
            okCount: okCount,
            notOkCount: notOkDays.count,
            minNotOkDays: notOkDays.min() ?? 0
        )

        if minCoverage == Int.max { return (0, "", 7, .empty, []) }
        return (minCoverage, minMedicineName, minThreshold, summary, coverages)
    }

    // MARK: - Early Refill Count

    private func computeEarlyRefillCount() -> (early: Int, total: Int) {
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) else { return (0, 0) }
        guard let request = Log.fetchRequest() as? NSFetchRequest<Log> else { return (0, 0) }
        request.predicate = NSPredicate(format: "type == 'purchase' AND timestamp >= %@", cutoff as NSDate)
        guard let purchases = try? context.fetch(request), !purchases.isEmpty else { return (0, 0) }

        var countedMeds = Set<NSManagedObjectID>()
        var earlyCount = 0
        var totalCount = 0

        for log in purchases {
            let medID = log.medicine.objectID
            guard countedMeds.insert(medID).inserted else { continue }
            guard let therapies = log.medicine.therapies, !therapies.isEmpty else { continue }

            totalCount += 1

            var stock: Double = 0
            var dailyConsumption: Double = 0
            for t in therapies {
                stock += Double(t.leftover())
                dailyConsumption += t.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            guard dailyConsumption > 0 else { continue }
            let days = Int(floor(stock / dailyConsumption))
            let threshold = log.medicine.stockThreshold(option: nil)
            if days > threshold { earlyCount += 1 }
        }
        return (earlyCount, totalCount)
    }

    private func computeCalmDaysStreak(dayAdherence: [DayAdherence], coverages: [MedicineCoverage]) -> Int {
        let hasNoStockOut = !coverages.isEmpty && coverages.allSatisfy { $0.days > 0 }
        guard hasNoStockOut else { return 0 }

        var streak = 0
        for day in dayAdherence.reversed() {
            let isPerfectAdherence = day.planned == 0 || day.percentage >= 1
            guard isPerfectAdherence else { break }
            streak += 1
        }
        return streak
    }

    private func filteredStartDay(for range: StatisticsRange, earliestStartDay: Date, endDay: Date) -> Date {
        let candidate: Date
        switch range {
        case .days:
            candidate = calendar.date(byAdding: .day, value: -6, to: endDay) ?? endDay
        case .weeks:
            candidate = calendar.date(byAdding: .day, value: -29, to: endDay) ?? endDay
        case .months:
            let comps = calendar.dateComponents([.year], from: endDay)
            candidate = calendar.date(from: DateComponents(year: comps.year, month: 1, day: 1)) ?? endDay
        case .all:
            candidate = earliestStartDay
        }
        return max(earliestStartDay, calendar.startOfDay(for: candidate))
    }

    private func computeTherapyMonitoringCorrelation(
        therapies: [Therapy],
        startDay: Date,
        endDay: Date
    ) -> TherapyMonitoringCorrelation? {
        let monitoredTherapyIDs = Set(therapies.compactMap { therapy -> NSManagedObjectID? in
            guard let monitoring = therapy.clinicalRulesValue?.monitoring else { return nil }
            return monitoring.isEmpty ? nil : therapy.objectID
        })

        let rangeStart = startDay
        guard let rangeEndExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else { return nil }

        let request: NSFetchRequest<MonitoringMeasurement> = MonitoringMeasurement.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "measured_at", ascending: true)]
        request.predicate = NSPredicate(
            format: "measured_at >= %@ AND measured_at < %@",
            rangeStart as NSDate,
            rangeEndExclusive as NSDate
        )

        guard let fetched = try? context.fetch(request), !fetched.isEmpty else { return nil }

        struct MeasurementWithTherapy {
            let measurement: MonitoringMeasurement
            let therapy: Therapy
        }

        let cleaned: [MeasurementWithTherapy] = fetched.compactMap { measurement in
            guard let value = measurement.primaryValue, value.isFinite, !value.isNaN else { return nil }
            if let linkedTherapy = measurement.therapy {
                return MeasurementWithTherapy(measurement: measurement, therapy: linkedTherapy)
            }

            guard let medicineId = measurement.medicine?.objectID else { return nil }
            let candidates = therapies.filter { $0.medicine.objectID == medicineId }
            guard !candidates.isEmpty else { return nil }

            if let monitored = candidates.first(where: { monitoredTherapyIDs.contains($0.objectID) }) {
                return MeasurementWithTherapy(measurement: measurement, therapy: monitored)
            }
            if candidates.count == 1, let only = candidates.first {
                return MeasurementWithTherapy(measurement: measurement, therapy: only)
            }
            let latest = candidates.max { ($0.start_date ?? .distantPast) < ($1.start_date ?? .distantPast) }
            guard let fallback = latest else { return nil }
            return MeasurementWithTherapy(measurement: measurement, therapy: fallback)
        }
        guard !cleaned.isEmpty else { return nil }

        // Prefer therapies explicitly configured with monitoring rules, fallback to any linked measurements.
        let preferred = cleaned.filter {
            monitoredTherapyIDs.contains($0.therapy.objectID)
        }
        let filtered = preferred.isEmpty ? cleaned : preferred

        let byTherapy = Dictionary(grouping: filtered) { $0.therapy.objectID }
        guard let selectedID = byTherapy.max(by: { $0.value.count < $1.value.count })?.key,
              let selectedEntries = byTherapy[selectedID] else { return nil }
        let therapyMeasurements = selectedEntries.map(\.measurement)
        guard let selectedTherapy = therapies.first(where: { $0.objectID == selectedID }) ?? selectedEntries.first?.therapy else {
            return nil
        }

        let dominantKindRaw = Dictionary(grouping: therapyMeasurements, by: { $0.kind })
            .max(by: { $0.value.count < $1.value.count })?.key
        let kindMeasurements = therapyMeasurements.filter {
            guard let value = $0.primaryValue else { return false }
            if value.isNaN || !value.isFinite { return false }
            return dominantKindRaw == nil || $0.kind == dominantKindRaw
        }
        guard !kindMeasurements.isEmpty else { return nil }

        let kind = dominantKindRaw.flatMap { MonitoringKind(rawValue: $0) }

        // Keep original measurement timestamps (no daily aggregation) so intra-day variations are visible.
        let parameterPoints = kindMeasurements.compactMap { measurement -> MonitoringCorrelationPoint? in
            guard let primary = measurement.primaryValue, primary.isFinite, !primary.isNaN else { return nil }

            // For blood pressure, use the average of systolic/diastolic when both are present.
            // This avoids a flat line when only one component changes.
            let effectiveValue: Double
            if kind == .bloodPressure,
               let secondary = measurement.secondaryValue,
               secondary.isFinite,
               !secondary.isNaN {
                effectiveValue = (primary + secondary) / 2.0
            } else {
                effectiveValue = primary
            }

            return MonitoringCorrelationPoint(date: measurement.measured_at, value: effectiveValue)
        }
        .sorted { $0.date < $1.date }
        guard let firstParameterDate = parameterPoints.first?.date, !parameterPoints.isEmpty else { return nil }

        var therapiesByMedicineId: [UUID: [Therapy]] = [:]
        var medicinesById: [UUID: Medicine] = [:]
        for therapy in therapies {
            medicinesById[therapy.medicine.id] = therapy.medicine
            therapiesByMedicineId[therapy.medicine.id, default: []].append(therapy)
        }

        let adherenceStart = max(rangeStart, calendar.startOfDay(for: firstParameterDate))
        let logsByMedicineDay = buildLogsIndex(
            medicinesById: medicinesById,
            startDay: adherenceStart,
            endDay: endDay
        )

        let therapyAdherenceByDay = Dictionary(uniqueKeysWithValues: makeDays(from: adherenceStart, to: endDay).compactMap { day -> (Date, Double)? in
            let planned = plannedCount(for: selectedTherapy, on: day)
            guard planned > 0 else { return nil }
            let taken = takenCount(
                for: selectedTherapy,
                on: day,
                therapiesByMedicineId: therapiesByMedicineId,
                logsByMedicineDay: logsByMedicineDay
            )
            let percentage = min(1, Double(taken) / Double(planned))
            return (day, percentage)
        })

        let globalByDay = Dictionary(uniqueKeysWithValues: dayAdherence.compactMap { d -> (Date, Double)? in
            guard d.percentage >= 0 else { return nil }
            let day = calendar.startOfDay(for: d.date)
            return (day, d.percentage)
        })

        let adherencePoints = parameterPoints.compactMap { point -> MonitoringCorrelationPoint? in
            let day = calendar.startOfDay(for: point.date)
            let value = therapyAdherenceByDay[day] ?? globalByDay[day]
            guard let value else { return nil }
            return MonitoringCorrelationPoint(date: point.date, value: value)
        }
        guard !adherencePoints.isEmpty else { return nil }

        let kindLabel = kind?.label ?? "Parametro"
        let unit = kindMeasurements.reversed().compactMap { $0.unit?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? defaultUnit(for: kind)

        let correlation = pearsonCorrelation(
            parameterPoints: parameterPoints,
            adherencePoints: adherencePoints
        )

        let smoothed = smoothPoints(parameterPoints)

        return TherapyMonitoringCorrelation(
            therapyTitle: selectedTherapy.medicine.nome,
            parameterTitle: kindLabel,
            parameterUnit: unit,
            parameterPoints: parameterPoints,
            smoothedParameterPoints: smoothed,
            adherencePoints: adherencePoints,
            correlationCoefficient: correlation
        )
    }

    private func defaultUnit(for kind: MonitoringKind?) -> String {
        switch kind {
        case .bloodPressure:
            return "mmHg"
        case .bloodGlucose:
            return "mg/dL"
        case .temperature:
            return "°C"
        case .heartRate:
            return "bpm"
        case nil:
            return ""
        }
    }

    // MARK: - Smoothing & Robust Domain

    /// Applies a symmetric moving average with an adaptive half-window.
    /// Window grows with data density so sparse series stay unmodified while
    /// noisy dense series show a clearly readable trend line.
    private func smoothPoints(_ points: [MonitoringCorrelationPoint]) -> [MonitoringCorrelationPoint] {
        let n = points.count
        let halfWindow: Int
        switch n {
        case ..<5:  return points          // too few points – no smoothing
        case ..<10: halfWindow = 1          // window of 3
        case ..<20: halfWindow = 2          // window of 5
        default:    halfWindow = 3          // window of 7
        }
        return points.enumerated().map { i, point in
            let lo = max(0, i - halfWindow)
            let hi = min(n - 1, i + halfWindow)
            let window = points[lo...hi]
            let avg = window.map(\.value).reduce(0.0, +) / Double(window.count)
            return MonitoringCorrelationPoint(date: point.date, value: avg)
        }
    }

    private func pearsonCorrelation(
        parameterPoints: [MonitoringCorrelationPoint],
        adherencePoints: [MonitoringCorrelationPoint]
    ) -> Double? {
        let adherenceByDay = Dictionary(uniqueKeysWithValues: adherencePoints.map { ($0.date, $0.value) })
        let pairs = parameterPoints.compactMap { point -> (Double, Double)? in
            guard let adherence = adherenceByDay[point.date] else { return nil }
            return (adherence, point.value)
        }
        guard pairs.count >= 3 else { return nil }

        let xs = pairs.map { $0.0 }
        let ys = pairs.map { $0.1 }
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)

        var num = 0.0
        var denX = 0.0
        var denY = 0.0
        for i in 0..<pairs.count {
            let dx = xs[i] - meanX
            let dy = ys[i] - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        let den = sqrt(denX * denY)
        guard den > 0 else { return nil }
        return num / den
    }

    // MARK: - Helpers

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
}
