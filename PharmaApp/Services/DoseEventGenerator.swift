import Foundation
import CoreData

struct DoseEvent {
    let date: Date
    let therapyId: NSManagedObjectID
    let medicineId: NSManagedObjectID
}

struct DoseEventGenerator {
    private let scheduleService: TherapyDoseScheduleService
    private let calendar: Calendar

    init(context: NSManagedObjectContext, calendar: Calendar = .current) {
        self.scheduleService = TherapyDoseScheduleService(context: context, calendar: calendar)
        self.calendar = calendar
    }

    func generateEvents(
        therapies: [Therapy],
        from rangeStart: Date,
        to end: Date
    ) -> [DoseEvent] {
        guard !therapies.isEmpty else { return [] }

        let startDay = calendar.startOfDay(for: rangeStart)
        let endDay = calendar.startOfDay(for: end)
        var day = startDay
        var events: [DoseEvent] = []

        while day <= endDay {
            for therapy in therapies {
                let scheduled = scheduleService.effectiveScheduledTimes(on: day, for: therapy)
                guard !scheduled.isEmpty else { continue }
                for date in scheduled {
                    guard date >= rangeStart && date <= end else { continue }
                    events.append(DoseEvent(date: date, therapyId: therapy.objectID, medicineId: therapy.medicine.objectID))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return events.sorted { $0.date < $1.date }
    }
}
