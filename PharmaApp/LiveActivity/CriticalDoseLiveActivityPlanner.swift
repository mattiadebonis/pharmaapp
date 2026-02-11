import Foundation
import CoreData

protocol CriticalDoseLiveActivityPlanning {
    func makePlan(now: Date?) -> CriticalDosePlan
}

struct CriticalDoseLiveActivityPlanner {
    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private let config: CriticalDoseLiveActivityConfig
    private let snoozeStore: CriticalDoseSnoozeStoreProtocol
    private let clock: Clock

    init(
        context: NSManagedObjectContext,
        calendar: Calendar = .current,
        config: CriticalDoseLiveActivityConfig = .default,
        snoozeStore: CriticalDoseSnoozeStoreProtocol = CriticalDoseSnoozeStore(),
        clock: Clock = SystemClock()
    ) {
        self.context = context
        self.calendar = calendar
        self.config = config
        self.snoozeStore = snoozeStore
        self.clock = clock
    }

    func makePlan(now overrideNow: Date? = nil) -> CriticalDosePlan {
        let now = overrideNow ?? clock.now()
        let windowStart = now.addingTimeInterval(-config.overdueToleranceInterval)
        let windowEnd = now.addingTimeInterval(config.leadTimeInterval)

        let therapies = fetchEligibleTherapies()
        guard !therapies.isEmpty else {
            return CriticalDosePlan(aggregate: nil, nextRefreshAt: nil)
        }

        let generator = DoseEventGenerator(context: context, calendar: calendar)
        let events = generator.generateEvents(therapies: therapies, from: windowStart, to: windowEnd)

        let therapyByObjectID = Dictionary(therapies.map { ($0.objectID, $0) }, uniquingKeysWith: { first, _ in first })
        var activeCandidates: [CriticalDoseCandidate] = []

        for event in events {
            guard let therapy = therapyByObjectID[event.therapyId] else { continue }
            guard !hasMatchingIntakeLog(for: event.date, therapy: therapy) else { continue }
            guard !snoozeStore.isSnoozed(therapyId: therapy.id, scheduledAt: event.date, now: now) else { continue }

            activeCandidates.append(
                CriticalDoseCandidate(
                    therapyId: therapy.id,
                    medicineId: therapy.medicine.id,
                    medicineName: therapy.medicine.nome,
                    doseText: doseText(for: therapy, scheduledAt: event.date),
                    scheduledAt: event.date
                )
            )
        }

        let sorted = activeCandidates.sorted { lhs, rhs in
            if lhs.scheduledAt == rhs.scheduledAt {
                return lhs.medicineName.localizedCaseInsensitiveCompare(rhs.medicineName) == .orderedAscending
            }
            return lhs.scheduledAt < rhs.scheduledAt
        }

        let aggregate: CriticalDoseAggregate?
        if let primary = sorted.first {
            let additionalCount = max(0, sorted.count - 1)
            let subtitleBase = "\(primary.medicineName) · \(primary.doseText)"
            let subtitle = additionalCount > 0 ? "\(subtitleBase) +\(additionalCount)" : subtitleBase
            let expiryAt = primary.scheduledAt.addingTimeInterval(config.overdueToleranceInterval)
            aggregate = CriticalDoseAggregate(
                primary: primary,
                additionalCount: additionalCount,
                subtitleDisplay: subtitle,
                expiryAt: expiryAt
            )
        } else {
            aggregate = nil
        }

        let nextRefreshAt = computeNextRefreshDate(now: now, therapies: therapies, visibleCandidates: sorted)
        return CriticalDosePlan(aggregate: aggregate, nextRefreshAt: nextRefreshAt)
    }

    private func computeNextRefreshDate(
        now: Date,
        therapies: [Therapy],
        visibleCandidates: [CriticalDoseCandidate]
    ) -> Date? {
        var checkpoints: [Date] = []

        for candidate in visibleCandidates {
            let threshold30 = candidate.scheduledAt.addingTimeInterval(-30 * 60)
            if threshold30 > now {
                checkpoints.append(threshold30)
            }

            let expiry = candidate.scheduledAt.addingTimeInterval(config.overdueToleranceInterval)
            if expiry > now {
                checkpoints.append(expiry)
            }
        }

        if let nextSnoozeExpiry = snoozeStore.nextExpiry(after: now) {
            checkpoints.append(nextSnoozeExpiry)
        }

        let recurrenceManager = RecurrenceManager(context: context)
        let searchAfter = now.addingTimeInterval(config.leadTimeInterval)
        for therapy in therapies {
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let startDate = therapy.start_date ?? now
            guard let occurrence = recurrenceManager.nextOccurrence(
                rule: rule,
                startDate: startDate,
                after: searchAfter,
                doses: therapy.doses as NSSet?
            ) else {
                continue
            }
            let entersWindowAt = occurrence.addingTimeInterval(-config.leadTimeInterval)
            if entersWindowAt > now {
                checkpoints.append(entersWindowAt)
            }
        }

        return checkpoints.filter { $0 > now }.sorted().first
    }

    private func fetchEligibleTherapies() -> [Therapy] {
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        do {
            let fetched = try context.fetch(request)
            return fetched.filter { therapy in
                guard let rrule = therapy.rrule, !rrule.isEmpty else { return false }
                guard let doses = therapy.doses, !doses.isEmpty else { return false }
                return true
            }
        } catch {
            return []
        }
    }

    private func doseText(for therapy: Therapy, scheduledAt: Date) -> String {
        let doses = therapy.doses ?? []
        guard !doses.isEmpty else { return "1 unità" }

        let targetHour = calendar.component(.hour, from: scheduledAt)
        let targetMinute = calendar.component(.minute, from: scheduledAt)
        let matching = doses.filter { dose in
            let hour = calendar.component(.hour, from: dose.time)
            let minute = calendar.component(.minute, from: dose.time)
            return hour == targetHour && minute == targetMinute
        }

        let relevant = matching.isEmpty ? Array(doses) : Array(matching)
        let amount = relevant.reduce(0.0) { $0 + $1.amountValue }
        let normalizedAmount = amount > 0 ? amount : 1
        let amountText: String
        if abs(normalizedAmount.rounded() - normalizedAmount) < 0.0001 {
            amountText = String(Int(normalizedAmount.rounded()))
        } else {
            amountText = String(format: "%.1f", normalizedAmount).replacingOccurrences(of: ".", with: ",")
        }
        return "\(amountText) \(doseUnit(for: therapy, amount: normalizedAmount))"
    }

    private func doseUnit(for therapy: Therapy, amount: Double) -> String {
        let tipologia = therapy.package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tipologia.contains("capsul") {
            return abs(amount - 1) < 0.0001 ? "capsula" : "capsule"
        }
        if tipologia.contains("compress") {
            return abs(amount - 1) < 0.0001 ? "compressa" : "compresse"
        }

        let fallback = therapy.package.unita.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !fallback.isEmpty {
            return fallback
        }
        return "unità"
    }

    private func hasMatchingIntakeLog(for eventDate: Date, therapy: Therapy) -> Bool {
        let tolerance = max(config.leadTimeInterval, config.overdueToleranceInterval)
        let intakeLogs = therapy.medicine.effectiveIntakeLogs()
        guard !intakeLogs.isEmpty else { return false }

        for log in intakeLogs {
            if let logTherapy = log.therapy {
                if logTherapy.objectID != therapy.objectID { continue }
            } else {
                let therapyCount = therapy.medicine.therapies?.count ?? 0
                if therapyCount == 1 {
                    // Accept logs without explicit therapy link when there is a single active therapy.
                } else if log.package != therapy.package {
                    continue
                }
            }

            let delta = abs(log.timestamp.timeIntervalSince(eventDate))
            if delta <= tolerance {
                return true
            }
        }

        return false
    }
}

extension CriticalDoseLiveActivityPlanner: CriticalDoseLiveActivityPlanning {}
