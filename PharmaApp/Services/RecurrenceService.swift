import Foundation
import CoreData

protocol RecurrenceServiceProtocol {
    func parseRecurrence(_ rrule: String) -> RecurrenceRule
    func nextOccurrence(rule: RecurrenceRule, startDate: Date, after: Date, doses: NSSet?) -> Date?
    func describe(rule: RecurrenceRule) -> String
}

/// Adapter che riusa l'attuale RecurrenceManager.
final class RecurrenceService: RecurrenceServiceProtocol {
    private let manager: RecurrenceManager

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.manager = RecurrenceManager(context: context)
    }

    func parseRecurrence(_ rrule: String) -> RecurrenceRule {
        manager.parseRecurrenceString(rrule)
    }

    func nextOccurrence(rule: RecurrenceRule, startDate: Date, after: Date, doses: NSSet?) -> Date? {
        manager.nextOccurrence(rule: rule, startDate: startDate, after: after, doses: doses)
    }

    func describe(rule: RecurrenceRule) -> String {
        manager.describeRecurrence(rule: rule)
    }
}
