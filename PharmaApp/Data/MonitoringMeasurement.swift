import Foundation
import CoreData

@objc(MonitoringMeasurement)
public class MonitoringMeasurement: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var created_at: Date
    @NSManaged public var measured_at: Date
    @NSManaged public var scheduled_at: Date?
    @NSManaged public var todo_source_id: String
    @NSManaged public var kind: String
    @NSManaged public var dose_relation: String?
    @NSManaged public var value_primary: NSNumber?
    @NSManaged public var value_secondary: NSNumber?
    @NSManaged public var unit: String?
    @NSManaged public var medicine: Medicine?
    @NSManaged public var therapy: Therapy?
}

extension MonitoringMeasurement {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MonitoringMeasurement> {
        NSFetchRequest<MonitoringMeasurement>(entityName: "MonitoringMeasurement")
    }

    static func fetchRequest(todoSourceID: String) -> NSFetchRequest<MonitoringMeasurement> {
        let request: NSFetchRequest<MonitoringMeasurement> = fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "todo_source_id == %@", todoSourceID)
        return request
    }

    static func fetchRequest(from start: Date, to end: Date) -> NSFetchRequest<MonitoringMeasurement> {
        let request: NSFetchRequest<MonitoringMeasurement> = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "measured_at", ascending: false)]
        request.predicate = NSPredicate(format: "measured_at >= %@ AND measured_at <= %@", start as NSDate, end as NSDate)
        return request
    }

    var primaryValue: Double? {
        value_primary?.doubleValue
    }

    var secondaryValue: Double? {
        value_secondary?.doubleValue
    }
}
