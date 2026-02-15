import Foundation
import CoreData
import os.signpost

struct AutoIntakeConfiguration {
    var backfillHours: Int = 24
    var logToleranceSeconds: TimeInterval = 60 * 60
    var maxEventsPerRun: Int = 120
}

final class AutoIntakeProcessor {
    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private let config: AutoIntakeConfiguration
    private let perfLog = OSLog(subsystem: "PharmaApp", category: "Performance")

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
        processDueIntakesBatch(now: now, saveAtEnd: true)
    }

    @discardableResult
    func processDueIntakesBatch(now: Date = Date(), saveAtEnd: Bool = true) -> Int {
        let signpostID = OSSignpostID(log: perfLog)
        os_signpost(.begin, log: perfLog, name: "AutoIntakeBatch", signpostID: signpostID)
        defer { os_signpost(.end, log: perfLog, name: "AutoIntakeBatch", signpostID: signpostID) }

        return context.performAndWait {
            let therapies = fetchAutoTherapies()
            guard !therapies.isEmpty else { return 0 }

            let start = calendar.date(byAdding: .hour, value: -config.backfillHours, to: now) ?? now
            let generator = DoseEventGenerator(context: context, calendar: calendar)
            let events = generator.generateEvents(therapies: therapies, from: start, to: now)
            guard !events.isEmpty else { return 0 }

            let lookup = Dictionary(therapies.map { ($0.objectID, $0) }, uniquingKeysWith: { first, _ in first })
            var intakeBucketsByTherapy = buildIntakeMinuteIndex(therapies: therapies)
            let toleranceMinutes = max(1, Int(ceil(config.logToleranceSeconds / 60)))
            let stockService = StockService(context: context)
            var createdCount = 0
            var processedCount = 0

            for event in events {
                guard let therapy = lookup[event.therapyId] else { continue }
                guard !requiresManualConfirmation(therapy) else { continue }
                guard !hasMatchingIntakeLog(
                    for: event.date,
                    therapy: therapy,
                    intakeBucketsByTherapy: intakeBucketsByTherapy,
                    toleranceMinutes: toleranceMinutes
                ) else { continue }

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
                    operationId: operationId,
                    save: false
                )
                if log != nil {
                    createdCount += 1
                    let minuteBucket = Self.minuteBucket(for: event.date)
                    intakeBucketsByTherapy[therapy.objectID, default: []].insert(minuteBucket)
                }

                processedCount += 1
                if processedCount >= config.maxEventsPerRun {
                    break
                }
            }

            if saveAtEnd, context.hasChanges {
                try? context.save()
            }

            return createdCount
        }
    }

    func nextAutoIntakeDate(now: Date = Date()) -> Date? {
        context.performAndWait {
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
        if let option = Option.current(in: context) {
            return option.manual_intake_registration
        }
        if therapy.manual_intake_registration { return true }
        if therapy.medicine.manual_intake_registration { return true }
        return false
    }

    private func buildIntakeMinuteIndex(therapies: [Therapy]) -> [NSManagedObjectID: Set<Int>] {
        var index: [NSManagedObjectID: Set<Int>] = [:]
        let therapiesByMedicine = Dictionary(grouping: therapies, by: { $0.medicine.objectID })

        for group in therapiesByMedicine.values {
            guard let firstTherapy = group.first else { continue }
            let intakeLogs = firstTherapy.medicine.effectiveIntakeLogs()
            guard !intakeLogs.isEmpty else { continue }

            let singleTherapy = group.count == 1 ? group[0] : nil
            let groupByObjectID = Dictionary(group.map { ($0.objectID, $0) }, uniquingKeysWith: { lhs, _ in lhs })

            for log in intakeLogs {
                let minuteBucket = Self.minuteBucket(for: log.timestamp)
                if let logTherapy = log.therapy {
                    index[logTherapy.objectID, default: []].insert(minuteBucket)
                    continue
                }

                if let singleTherapy {
                    index[singleTherapy.objectID, default: []].insert(minuteBucket)
                    continue
                }

                for therapy in groupByObjectID.values where log.package == therapy.package {
                    index[therapy.objectID, default: []].insert(minuteBucket)
                }
            }
        }

        return index
    }

    private func hasMatchingIntakeLog(
        for eventDate: Date,
        therapy: Therapy,
        intakeBucketsByTherapy: [NSManagedObjectID: Set<Int>],
        toleranceMinutes: Int
    ) -> Bool {
        guard let buckets = intakeBucketsByTherapy[therapy.objectID], !buckets.isEmpty else { return false }
        let center = Self.minuteBucket(for: eventDate)
        let lower = center - toleranceMinutes
        let upper = center + toleranceMinutes
        for bucket in lower...upper where buckets.contains(bucket) {
            return true
        }
        return false
    }

    private static func minuteBucket(for date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }
}
