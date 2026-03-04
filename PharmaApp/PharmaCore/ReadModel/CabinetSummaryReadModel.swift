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
    case imminentDose = 3
    case refillWithinToday = 4
    case refillSoon = 5
    case nextDoseToday = 6
    case allUnderControl = 7

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

public struct CabinetInlineAction {
    public let text: String
    public let priority: CabinetSummaryPriority

    public init(text: String, priority: CabinetSummaryPriority) {
        self.text = text
        self.priority = priority
    }
}

public struct CabinetSummaryPresentation {
    public let summary: CabinetSummary
    public let inlineAction: CabinetInlineAction

    public init(summary: CabinetSummary, inlineAction: CabinetInlineAction) {
        self.summary = summary
        self.inlineAction = inlineAction
    }
}

// MARK: - Internal Analysis Types (shared with CabinetSummaryPresenter)

struct MedicineAnalysis {
    let medicineName: String
    let missedDoseTimes: [Date]
    let pendingDoseTimes: [Date]
    let nextScheduledDoseTime: Date?
    let autonomyDays: Int?
    let isLowStock: Bool
    let stockCoversNextDose: Bool
}

struct TimedActionCandidate {
    let medicineName: String
    let time: Date
}

struct RefillActionCandidate {
    let medicineName: String
    let nextDoseTime: Date?
    let autonomyDays: Int?
}

struct AggregatedAnalysis {
    let earliestMissedDoseTime: Date?
    let totalMissedDoseCount: Int
    let missedDoseCandidate: TimedActionCandidate?
    let nextUpcomingDoseTime: Date?
    let totalPendingDoseCount: Int
    let nextDoseCandidate: TimedActionCandidate?
    let nextScheduledDoseTime: Date?
    let refillBeforeNextDoseCount: Int
    let refillBeforeNextDoseCandidate: RefillActionCandidate?
    let refillWithinTodayCount: Int
    let refillWithinTodayCandidate: RefillActionCandidate?
    let refillSoonCount: Int
    let refillSoonCandidate: RefillActionCandidate?
    let hasAnyStockIssue: Bool
    let imminentDoseTime: Date?
    let imminentDoseMinutesAway: Int?
}

// MARK: - CabinetSummaryReadModel

public struct CabinetSummaryReadModel {
    private let recurrenceService: RecurrencePort
    private let calendar: Calendar

    public init(recurrenceService: RecurrencePort, calendar: Calendar = .current) {
        self.recurrenceService = recurrenceService
        self.calendar = calendar
    }

    // MARK: - Public API

    public func buildPresentation(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        pharmacy: PharmacyInfo?,
        now: Date = Date()
    ) -> CabinetSummaryPresentation {
        guard let option else {
            return CabinetSummaryPresentation(
                summary: .allUnderControl,
                inlineAction: .allUnderControl
            )
        }

        let doseSchedule = DoseScheduleReadModel(recurrenceService: recurrenceService, calendar: calendar)
        let analyses = medicines.map { analyzeMedicine($0, option: option, doseSchedule: doseSchedule, now: now) }
        let aggregated = aggregate(analyses, now: now)

        let presenter = CabinetSummaryPresenter(calendar: calendar)
        let summary = presenter.resolveSummary(from: aggregated, pharmacy: pharmacy)
        let inlineAction = presenter.resolveInlineAction(from: aggregated)
        return CabinetSummaryPresentation(summary: summary, inlineAction: inlineAction)
    }

    public func buildSummary(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        pharmacy: PharmacyInfo?,
        now: Date = Date()
    ) -> CabinetSummary {
        buildPresentation(medicines: medicines, option: option, pharmacy: pharmacy, now: now).summary
    }

    public func buildInlineAction(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        pharmacy: PharmacyInfo?,
        now: Date = Date()
    ) -> CabinetInlineAction {
        buildPresentation(medicines: medicines, option: option, pharmacy: pharmacy, now: now).inlineAction
    }

    public func buildLines(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        pharmacy: PharmacyInfo?,
        now: Date = Date()
    ) -> [String] {
        let summary = buildPresentation(
            medicines: medicines,
            option: option,
            pharmacy: pharmacy,
            now: now
        ).summary
        return [summary.title, summary.subtitle].filter { !$0.isEmpty }
    }

    // MARK: - Per-Medicine Analysis

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
            medicineName: displayMedicineName(medicine.name),
            missedDoseTimes: allMissedTimes.sorted(),
            pendingDoseTimes: allPendingTimes.sorted(),
            nextScheduledDoseTime: earliestNextDose,
            autonomyDays: autonomy,
            isLowStock: lowStock,
            stockCoversNextDose: coversNext
        )
    }

    // MARK: - Aggregation

    private func aggregate(_ analyses: [MedicineAnalysis], now: Date) -> AggregatedAnalysis {
        var earliestMissed: Date?
        var totalMissed = 0
        var missedCandidate: TimedActionCandidate?
        var nextUpcoming: Date?
        var nextScheduled: Date?
        var totalPending = 0
        var nextDoseCandidate: TimedActionCandidate?
        var refillBeforeNext = 0
        var refillBeforeNextCandidate: RefillActionCandidate?
        var refillWithinToday = 0
        var refillWithinTodayCandidate: RefillActionCandidate?
        var refillSoon = 0
        var refillSoonCandidate: RefillActionCandidate?
        var anyStockIssue = false

        for a in analyses {
            totalMissed += a.missedDoseTimes.count
            if let first = a.missedDoseTimes.first {
                if earliestMissed == nil || first < earliestMissed! {
                    earliestMissed = first
                }
                missedCandidate = preferredTimedCandidate(
                    current: missedCandidate,
                    new: TimedActionCandidate(medicineName: a.medicineName, time: first)
                )
            }

            totalPending += a.pendingDoseTimes.count
            if let first = a.pendingDoseTimes.first {
                if nextUpcoming == nil || first < nextUpcoming! {
                    nextUpcoming = first
                }
                nextDoseCandidate = preferredTimedCandidate(
                    current: nextDoseCandidate,
                    new: TimedActionCandidate(medicineName: a.medicineName, time: first)
                )
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
                    refillBeforeNextCandidate = preferredRefillBeforeNextCandidate(
                        current: refillBeforeNextCandidate,
                        new: RefillActionCandidate(
                            medicineName: a.medicineName,
                            nextDoseTime: a.nextScheduledDoseTime,
                            autonomyDays: a.autonomyDays
                        )
                    )
                } else if let days = a.autonomyDays, days <= 1, a.stockCoversNextDose {
                    refillWithinToday += 1
                    refillWithinTodayCandidate = preferredRefillWithinTodayCandidate(
                        current: refillWithinTodayCandidate,
                        new: RefillActionCandidate(
                            medicineName: a.medicineName,
                            nextDoseTime: a.nextScheduledDoseTime,
                            autonomyDays: a.autonomyDays
                        )
                    )
                } else {
                    refillSoon += 1
                    refillSoonCandidate = preferredRefillSoonCandidate(
                        current: refillSoonCandidate,
                        new: RefillActionCandidate(
                            medicineName: a.medicineName,
                            nextDoseTime: a.nextScheduledDoseTime,
                            autonomyDays: a.autonomyDays
                        )
                    )
                }
            }
        }

        // Compute imminent dose
        let windowSeconds = Double(CabinetSummaryPresenter.imminentDoseWindowMinutes) * 60
        var imminentTime: Date?
        var imminentMinutes: Int?
        if let upcoming = nextUpcoming {
            let secondsAway = upcoming.timeIntervalSince(now)
            if secondsAway > 0, secondsAway <= windowSeconds {
                imminentTime = upcoming
                imminentMinutes = max(1, Int(ceil(secondsAway / 60)))
            }
        }

        return AggregatedAnalysis(
            earliestMissedDoseTime: earliestMissed,
            totalMissedDoseCount: totalMissed,
            missedDoseCandidate: missedCandidate,
            nextUpcomingDoseTime: nextUpcoming,
            totalPendingDoseCount: totalPending,
            nextDoseCandidate: nextDoseCandidate,
            nextScheduledDoseTime: nextScheduled,
            refillBeforeNextDoseCount: refillBeforeNext,
            refillBeforeNextDoseCandidate: refillBeforeNextCandidate,
            refillWithinTodayCount: refillWithinToday,
            refillWithinTodayCandidate: refillWithinTodayCandidate,
            refillSoonCount: refillSoon,
            refillSoonCandidate: refillSoonCandidate,
            hasAnyStockIssue: anyStockIssue,
            imminentDoseTime: imminentTime,
            imminentDoseMinutesAway: imminentMinutes
        )
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

    private func preferredTimedCandidate(
        current: TimedActionCandidate?,
        new: TimedActionCandidate
    ) -> TimedActionCandidate {
        guard let current else { return new }
        if new.time != current.time {
            return new.time < current.time ? new : current
        }
        return nameSortKey(new.medicineName) < nameSortKey(current.medicineName) ? new : current
    }

    private func preferredRefillBeforeNextCandidate(
        current: RefillActionCandidate?,
        new: RefillActionCandidate
    ) -> RefillActionCandidate {
        guard let current else { return new }
        let currentTime = current.nextDoseTime ?? .distantFuture
        let newTime = new.nextDoseTime ?? .distantFuture
        if newTime != currentTime {
            return newTime < currentTime ? new : current
        }
        return nameSortKey(new.medicineName) < nameSortKey(current.medicineName) ? new : current
    }

    private func preferredRefillWithinTodayCandidate(
        current: RefillActionCandidate?,
        new: RefillActionCandidate
    ) -> RefillActionCandidate {
        preferredRefillBeforeNextCandidate(current: current, new: new)
    }

    private func preferredRefillSoonCandidate(
        current: RefillActionCandidate?,
        new: RefillActionCandidate
    ) -> RefillActionCandidate {
        guard let current else { return new }
        let currentAutonomy = current.autonomyDays ?? Int.max
        let newAutonomy = new.autonomyDays ?? Int.max
        if newAutonomy != currentAutonomy {
            return newAutonomy < currentAutonomy ? new : current
        }
        let currentTime = current.nextDoseTime ?? .distantFuture
        let newTime = new.nextDoseTime ?? .distantFuture
        if newTime != currentTime {
            return newTime < currentTime ? new : current
        }
        return nameSortKey(new.medicineName) < nameSortKey(current.medicineName) ? new : current
    }

    // MARK: - Name Helpers

    private func displayMedicineName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Farmaco" }
        return trimmed.localizedCapitalized
    }

    private func nameSortKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

// MARK: - CabinetSummary convenience

extension CabinetSummary {
    static let allUnderControl = CabinetSummary(
        title: CabinetSummaryCopy.allUnderControlTitle,
        subtitle: CabinetSummaryCopy.allUnderControlSubtitle,
        state: .ok,
        priority: .allUnderControl
    )
}

extension CabinetInlineAction {
    static let allUnderControl = CabinetInlineAction(
        text: CabinetSummaryCopy.inlineAllUnderControl,
        priority: .allUnderControl
    )
}
