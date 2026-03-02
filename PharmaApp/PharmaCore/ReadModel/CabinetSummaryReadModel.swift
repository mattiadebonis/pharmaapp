import Foundation

// MARK: - Public Types

public struct PharmacyInfo {
    public let name: String?
    public let isOpen: Bool?
    public let distanceText: String?

    public init(name: String?, isOpen: Bool?, distanceText: String?) {
        self.name = name
        self.isOpen = isOpen
        self.distanceText = distanceText
    }
}

public enum CabinetSummaryPriority: Int, Comparable {
    case missedDose = 1
    case refillBeforeNextDose = 2
    case refillWithinToday = 3
    case refillSoon = 4
    case nextDoseToday = 5
    case allUnderControl = 6

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum CabinetSummaryState {
    case critical
    case warning
    case info
    case ok
}

public struct CabinetSummary {
    public let title: String
    public let subtitle: String
    public let state: CabinetSummaryState
    public let priority: CabinetSummaryPriority

    public init(title: String, subtitle: String, state: CabinetSummaryState, priority: CabinetSummaryPriority) {
        self.title = title
        self.subtitle = subtitle
        self.state = state
        self.priority = priority
    }
}

// MARK: - CabinetSummaryReadModel

public struct CabinetSummaryReadModel {
    private let recurrenceService: RecurrencePort
    private let calendar: Calendar

    public init(recurrenceService: RecurrencePort, calendar: Calendar = .current) {
        self.recurrenceService = recurrenceService
        self.calendar = calendar
    }

    // MARK: - Centralized Copy

    private enum Copy {
        static let missedDoseTitle = "Una terapia di oggi richiede attenzione."
        static func missedDoseSubtitle(time: String) -> String {
            "La prima assunzione non completata era prevista alle \(time)."
        }
        static func missedDoseSubtitleWithPharmacy(time: String, distance: String) -> String {
            "La prima assunzione non completata era prevista alle \(time); farmacia vicina a \(distance)."
        }

        static let refillBeforeNextDoseTitle = "Serve un rifornimento prima della prossima assunzione."
        static func refillBeforeNextDoseTimePart(time: String) -> String {
            "La prossima è prevista alle \(time)"
        }
        static let refillBeforeNextDoseTimePartFallback = "La prossima assunzione è imminente"
        static func refillBeforeNextDoseSubtitle(timePart: String, distancePart: String) -> String {
            "\(timePart)\(distancePart)."
        }
        static func refillBeforeNextDosePluralTitle(count: Int) -> String {
            "\(count) farmaci in terapia oggi necessitano di rifornimento."
        }

        static func refillWithinTodayTitle(count: Int) -> String {
            count == 1
                ? "1 farmaco va rifornito entro oggi."
                : "\(count) farmaci vanno riforniti entro oggi."
        }

        static func refillSoonTitle(count: Int) -> String {
            count == 1
                ? "1 farmaco richiede rifornimento a breve."
                : "\(count) farmaci richiedono rifornimento a breve."
        }

        static func nextDoseTodayTitle(count: Int) -> String {
            count == 1
                ? "Oggi resta 1 assunzione da completare."
                : "Oggi restano \(count) assunzioni da completare."
        }
        static func nextDoseTodaySubtitle(time: String) -> String {
            "La prossima è prevista alle \(time)."
        }

        static func pharmacyNearby(distance: String) -> String {
            "La farmacia più vicina è a \(distance)."
        }

        static let allUnderControlTitle = "Tutto sotto controllo."
        static let allUnderControlSubtitle = "Le terapie sono coperte e le scorte sono adeguate."
    }

    // MARK: - Public API

    public func buildSummary(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        pharmacy: PharmacyInfo?,
        now: Date = Date()
    ) -> CabinetSummary {
        guard let option else {
            return .allUnderControl
        }

        let doseSchedule = DoseScheduleReadModel(recurrenceService: recurrenceService, calendar: calendar)
        let analyses = medicines.map { analyzeMedicine($0, option: option, doseSchedule: doseSchedule, now: now) }
        let aggregated = aggregate(analyses)

        return resolveSummary(from: aggregated, pharmacy: pharmacy)
    }

    public func buildLines(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        pharmacy: PharmacyInfo?,
        now: Date = Date()
    ) -> [String] {
        let summary = buildSummary(medicines: medicines, option: option, pharmacy: pharmacy, now: now)
        return [summary.title, summary.subtitle].filter { !$0.isEmpty }
    }

    // MARK: - Private Analysis

    private struct MedicineAnalysis {
        let missedDoseTimes: [Date]
        let pendingDoseTimes: [Date]
        let nextScheduledDoseTime: Date?
        let autonomyDays: Int?
        let isLowStock: Bool
        let stockCoversNextDose: Bool
    }

    private struct AggregatedAnalysis {
        let earliestMissedDoseTime: Date?
        let totalMissedDoseCount: Int
        let nextUpcomingDoseTime: Date?
        let totalPendingDoseCount: Int
        let nextScheduledDoseTime: Date?
        let refillBeforeNextDoseCount: Int
        let refillWithinTodayCount: Int
        let refillSoonCount: Int
        let hasAnyStockIssue: Bool
    }

    private func analyzeMedicine(
        _ medicine: MedicineSnapshot,
        option: OptionSnapshot,
        doseSchedule: DoseScheduleReadModel,
        now: Date
    ) -> MedicineAnalysis {
        let lowStock = isLowStock(medicine, option: option)
        let autonomy = autonomyDays(for: medicine)

        let manualTherapies = medicine.therapies.filter {
            $0.manualIntakeRegistration || medicine.manualIntakeRegistration
        }

        var allMissedTimes: [Date] = []
        var allPendingTimes: [Date] = []
        var earliestNextDose: Date?

        let intakeLogs = medicine.effectiveIntakeLogs(on: now, calendar: calendar)

        for therapy in manualTherapies {
            let schedule = doseSchedule.baseScheduledTimes(on: now, for: therapy)
            let therapyLogs = intakeLogs.filter { $0.therapyId == therapy.id || $0.therapyId == nil }
            let completed = completedBuckets(schedule: schedule, intakeLogs: therapyLogs, on: now)
            let pending = schedule.filter { !completed.contains(minuteBucket(for: $0)) }

            allMissedTimes.append(contentsOf: pending.filter { $0 <= now })
            allPendingTimes.append(contentsOf: pending.filter { $0 > now })
        }

        // Find next scheduled dose across all therapies (manual and non-manual affect stock)
        for therapy in medicine.therapies {
            if let next = doseSchedule.nextScheduledTime(for: therapy, after: now) {
                if earliestNextDose == nil || next < earliestNextDose! {
                    earliestNextDose = next
                }
            }
        }

        let coversNext = stockCoversNextDose(for: medicine, nextDoseTime: earliestNextDose)

        return MedicineAnalysis(
            missedDoseTimes: allMissedTimes.sorted(),
            pendingDoseTimes: allPendingTimes.sorted(),
            nextScheduledDoseTime: earliestNextDose,
            autonomyDays: autonomy,
            isLowStock: lowStock,
            stockCoversNextDose: coversNext
        )
    }

    private func aggregate(_ analyses: [MedicineAnalysis]) -> AggregatedAnalysis {
        var earliestMissed: Date?
        var totalMissed = 0
        var nextUpcoming: Date?
        var nextScheduled: Date?
        var totalPending = 0
        var refillBeforeNext = 0
        var refillWithinToday = 0
        var refillSoon = 0
        var anyStockIssue = false

        for a in analyses {
            totalMissed += a.missedDoseTimes.count
            if let first = a.missedDoseTimes.first {
                if earliestMissed == nil || first < earliestMissed! {
                    earliestMissed = first
                }
            }

            totalPending += a.pendingDoseTimes.count
            if let first = a.pendingDoseTimes.first {
                if nextUpcoming == nil || first < nextUpcoming! {
                    nextUpcoming = first
                }
            }

            if let next = a.nextScheduledDoseTime {
                if nextScheduled == nil || next < nextScheduled! {
                    nextScheduled = next
                }
            }

            if a.isLowStock {
                anyStockIssue = true

                if a.autonomyDays == 0, a.nextScheduledDoseTime != nil, !a.stockCoversNextDose {
                    refillBeforeNext += 1
                } else if let days = a.autonomyDays, days <= 1, a.stockCoversNextDose {
                    refillWithinToday += 1
                } else {
                    refillSoon += 1
                }
            }
        }

        return AggregatedAnalysis(
            earliestMissedDoseTime: earliestMissed,
            totalMissedDoseCount: totalMissed,
            nextUpcomingDoseTime: nextUpcoming,
            totalPendingDoseCount: totalPending,
            nextScheduledDoseTime: nextScheduled,
            refillBeforeNextDoseCount: refillBeforeNext,
            refillWithinTodayCount: refillWithinToday,
            refillSoonCount: refillSoon,
            hasAnyStockIssue: anyStockIssue
        )
    }

    // MARK: - Decision Tree

    private func resolveSummary(from a: AggregatedAnalysis, pharmacy: PharmacyInfo?) -> CabinetSummary {
        // 1. Missed dose
        if a.totalMissedDoseCount > 0, let missedTime = a.earliestMissedDoseTime {
            let time = formatTime(missedTime)
            let subtitle: String
            if a.hasAnyStockIssue, let distance = pharmacyDistanceText(from: pharmacy) {
                subtitle = Copy.missedDoseSubtitleWithPharmacy(time: time, distance: distance)
            } else {
                subtitle = Copy.missedDoseSubtitle(time: time)
            }
            return CabinetSummary(
                title: Copy.missedDoseTitle,
                subtitle: subtitle,
                state: .critical,
                priority: .missedDose
            )
        }

        // 2. Refill before next dose
        if a.refillBeforeNextDoseCount > 0 {
            let n = a.refillBeforeNextDoseCount
            if n == 1 {
                let distancePart = pharmacyDistanceText(from: pharmacy).map { "; farmacia vicina a \($0)" } ?? ""
                let timePart: String
                if let nextTime = a.nextScheduledDoseTime {
                    timePart = Copy.refillBeforeNextDoseTimePart(time: formatTime(nextTime))
                } else {
                    timePart = Copy.refillBeforeNextDoseTimePartFallback
                }
                return CabinetSummary(
                    title: Copy.refillBeforeNextDoseTitle,
                    subtitle: Copy.refillBeforeNextDoseSubtitle(timePart: timePart, distancePart: distancePart),
                    state: .critical,
                    priority: .refillBeforeNextDose
                )
            } else {
                let pharmacySubtitle = pharmacyDistanceText(from: pharmacy)
                    .map { Copy.pharmacyNearby(distance: $0) } ?? ""
                return CabinetSummary(
                    title: Copy.refillBeforeNextDosePluralTitle(count: n),
                    subtitle: pharmacySubtitle,
                    state: .critical,
                    priority: .refillBeforeNextDose
                )
            }
        }

        // 3. Refill within today (promoted from old priority 4)
        if a.refillWithinTodayCount > 0 {
            let n = a.refillWithinTodayCount
            let subtitle = pharmacyDistanceText(from: pharmacy)
                .map { Copy.pharmacyNearby(distance: $0) } ?? ""
            return CabinetSummary(
                title: Copy.refillWithinTodayTitle(count: n),
                subtitle: subtitle,
                state: .warning,
                priority: .refillWithinToday
            )
        }

        // 4. Refill soon (promoted from old priority 5)
        if a.refillSoonCount > 0 {
            let n = a.refillSoonCount
            let subtitle = pharmacyDistanceText(from: pharmacy)
                .map { Copy.pharmacyNearby(distance: $0) } ?? ""
            return CabinetSummary(
                title: Copy.refillSoonTitle(count: n),
                subtitle: subtitle,
                state: .info,
                priority: .refillSoon
            )
        }

        // 5. Next dose today (demoted from old priority 3)
        if a.totalPendingDoseCount > 0 {
            let n = a.totalPendingDoseCount
            var subtitle = ""
            if let nextTime = a.nextUpcomingDoseTime {
                subtitle = Copy.nextDoseTodaySubtitle(time: formatTime(nextTime))
            }
            return CabinetSummary(
                title: Copy.nextDoseTodayTitle(count: n),
                subtitle: subtitle,
                state: .warning,
                priority: .nextDoseToday
            )
        }

        // 6. All under control
        return .allUnderControl
    }

    // MARK: - Stock Helpers

    private func isLowStock(_ medicine: MedicineSnapshot, option: OptionSnapshot) -> Bool {
        if let autonomyDays = autonomyDays(for: medicine) {
            return autonomyDays < medicine.stockThreshold(option: option)
        }

        if let remainingUnits = medicine.stockUnitsWithoutTherapy {
            return remainingUnits < medicine.stockThreshold(option: option)
        }

        return false
    }

    private func autonomyDays(for medicine: MedicineSnapshot) -> Int? {
        guard !medicine.therapies.isEmpty else { return nil }

        var totalLeftover: Double = 0
        var totalDaily: Double = 0
        for therapy in medicine.therapies {
            totalLeftover += Double(therapy.leftoverUnits)
            totalDaily += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
        }

        if totalLeftover <= 0 { return 0 }
        guard totalDaily > 0 else { return nil }

        return max(0, Int(floor(totalLeftover / totalDaily)))
    }

    private func stockCoversNextDose(for medicine: MedicineSnapshot, nextDoseTime: Date?) -> Bool {
        guard nextDoseTime != nil else { return true }
        let totalLeftover = medicine.therapies.reduce(0.0) { $0 + Double($1.leftoverUnits) }
        let minDoseAmount = medicine.therapies
            .flatMap(\.doses)
            .map(\.amount)
            .min() ?? 1.0
        return totalLeftover >= minDoseAmount
    }

    // MARK: - Dose Schedule Helpers

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

    private func minuteBucket(for date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    // MARK: - Formatting Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func pharmacyDistanceText(from pharmacy: PharmacyInfo?) -> String? {
        guard let text = pharmacy?.distanceText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else { return nil }
        return text.replacingOccurrences(of: " · ", with: " o ")
    }
}

// MARK: - CabinetSummary convenience

extension CabinetSummary {
    static let allUnderControl = CabinetSummary(
        title: "Tutto sotto controllo.",
        subtitle: "Le terapie sono coperte e le scorte sono adeguate.",
        state: .ok,
        priority: .allUnderControl
    )
}
