import Foundation
import CoreData

@objc(CustomFilter)
public class CustomFilter: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var owner_user_id: String?
    @NSManaged public var name: String
    @NSManaged public var query: String
    @NSManaged public var position: Int32
    @NSManaged public var created_at: Date?
    @NSManaged public var updated_at: Date?
    @NSManaged public var deleted_at: Date?
    @NSManaged public var source_id: UUID?
    @NSManaged public var visibility: String?
    @NSManaged public var synced_at: Date?
}

extension CustomFilter {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CustomFilter> {
        NSFetchRequest<CustomFilter>(entityName: "CustomFilter")
    }

    static func extractFilters() -> NSFetchRequest<CustomFilter> {
        let request = CustomFilter.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "position", ascending: true),
            NSSortDescriptor(key: "created_at", ascending: true)
        ]
        return request
    }

    static func extractActiveFilters(ownerUserID: String) -> NSFetchRequest<CustomFilter> {
        let request = extractFilters()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "deleted_at == nil"),
            NSPredicate(format: "owner_user_id == %@", ownerUserID)
        ])
        return request
    }

    var isDeletedFilter: Bool {
        deleted_at != nil
    }
}
