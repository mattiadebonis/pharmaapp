import Foundation
import CoreData

struct AutoIntakeConfiguration {
    var backfillHours: Int = 24
    var logToleranceSeconds: TimeInterval = 60 * 60
    var maxEventsPerRun: Int = 120
}

@MainActor
final class AutoIntakeProcessor {
    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private let config: AutoIntakeConfiguration

    init(
        context: NSManagedObjectContext,
        calendar: Calendar = .current,
        config: AutoIntakeConfiguration = AutoIntakeConfiguration()
    ) {
        self.context = context
        self.calendar = calendar
        self.config = config
    }

    @discardableResult
    func processDueIntakes(now: Date = Date()) -> Int {
        let therapies = fetchAutoTherapies()
        guard !therapies.isEmpty else { return 0 }

        let start = calendar.date(byAdding: .hour, value: -config.backfillHours, to: now) ?? now
        let generator = DoseEventGenerator(context: context, calendar: calendar)
        let events = generator.generateEvents(therapies: therapies, from: start, to: now)
        guard !events.isEmpty else { return 0 }

        let lookup = Dictionary(uniqueKeysWithValues: therapies.map { ($0.objectID, $0) })
        let stockService = StockService(context: context)
        var createdCount = 0
        var processedCount = 0

        for event in events {
            guard let therapy = lookup[event.therapyId] else { continue }
            guard !requiresManualConfirmation(therapy) else { continue }
            guard !hasMatchingIntakeLog(for: event, therapy: therapy, tolerance: config.logToleranceSeconds) else {
                continue
            }
            let operationId = OperationIdProvider.shared.operationId(
                for: OperationKey.autoIntake(therapyId: therapy.id, scheduledAt: event.date),
                ttl: 24 * 60 * 60
            )
            let log = stockService.createLog(
                type: "intake",
                medicine: therapy.medicine,
                package: therapy.package,
                therapy: therapy,
                timestamp: event.date,
                operationId: operationId
            )
            if log != nil {
                createdCount += 1
            }
            processedCount += 1
            if processedCount >= config.maxEventsPerRun {
                break
            }
        }

        return createdCount
    }

    func nextAutoIntakeDate(now: Date = Date()) -> Date? {
        let therapies = fetchAutoTherapies()
        guard !therapies.isEmpty else { return nil }

        let recurrenceManager = RecurrenceManager(context: context)
        let candidates: [Date] = therapies.compactMap { therapy in
            guard !requiresManualConfirmation(therapy) else { return nil }
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? now
            return recurrenceManager.nextOccurrence(
                rule: rule,
                startDate: start,
                after: now,
                doses: therapy.doses as NSSet?
            )
        }

        return candidates.sorted().first
    }

    private func fetchAutoTherapies() -> [Therapy] {
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        do {
            let therapies = try context.fetch(request)
            return therapies.filter { therapy in
                guard let rrule = therapy.rrule, !rrule.isEmpty else { return false }
                guard let doses = therapy.doses, !doses.isEmpty else { return false }
                return !requiresManualConfirmation(therapy)
            }
        } catch {
            return []
        }
    }

    private func requiresManualConfirmation(_ therapy: Therapy) -> Bool {
        if therapy.manual_intake_registration { return true }
        if therapy.medicine.manual_intake_registration { return true }
        return false
    }

    private func hasMatchingIntakeLog(
        for event: DoseEvent,
        therapy: Therapy,
        tolerance: TimeInterval
    ) -> Bool {
        let intakeLogs = therapy.medicine.effectiveIntakeLogs()
        guard !intakeLogs.isEmpty else { return false }

        for log in intakeLogs {
            if let logTherapy = log.therapy {
                if logTherapy.objectID != therapy.objectID { continue }
            } else {
                let therapyCount = therapy.medicine.therapies?.count ?? 0
                if therapyCount == 1 {
                    // accept the unassigned log
                } else if log.package != therapy.package {
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
}
