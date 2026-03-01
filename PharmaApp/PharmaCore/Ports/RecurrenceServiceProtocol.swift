import Foundation

public protocol RecurrencePort {
    func parseRecurrenceString(_ icsString: String) -> RecurrenceRule
    func allowedEvents(on day: Date, rule: RecurrenceRule, startDate: Date, dosesPerDay: Int, calendar: Calendar) -> Int
    func nextOccurrence(rule: RecurrenceRule, startDate: Date, after: Date, doses: [DoseSnapshot], calendar: Calendar) -> Date?
}
