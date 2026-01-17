import Foundation
import CoreData

struct DoseEvent {
    let date: Date
    let therapyId: NSManagedObjectID
    let medicineId: NSManagedObjectID
}

struct DoseEventGenerator {
    private let recurrenceManager: RecurrenceManager
    private let calendar: Calendar

    init(context: NSManagedObjectContext, calendar: Calendar = .current) {
        self.recurrenceManager = RecurrenceManager(context: context)
        self.calendar = calendar
    }

    func generateEvents(
        therapies: [Therapy],
        from start: Date,
        to end: Date
    ) -> [DoseEvent] {
        let eligible = therapies.filter { !$0.manual_intake_registration }
        guard !eligible.isEmpty else { return [] }

        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        var day = startDay
        var events: [DoseEvent] = []

        while day <= endDay {
            for therapy in eligible {
                guard let doseSet = therapy.doses, !doseSet.isEmpty else { continue }
                let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
                let start = therapy.start_date ?? day
                let sortedDoses = doseSet.sorted { $0.time < $1.time }
                let perDay = max(1, sortedDoses.count)
                let allowed = recurrenceManager.allowedEvents(
                    on: day,
                    rule: rule,
                    startDate: start,
                    dosesPerDay: perDay,
                    calendar: calendar
                )
                guard allowed > 0 else { continue }

                let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
                for dose in limitedDoses {
                    let time = dose.time
                    guard let date = combine(day: day, withTime: time) else { continue }
                    guard date >= start && date <= end else { continue }
                    events.append(DoseEvent(date: date, therapyId: therapy.objectID, medicineId: therapy.medicine.objectID))
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
