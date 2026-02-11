import Foundation
import CoreData

@objc(MedicineComment)
public final class MedicineComment: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var text: String?
    @NSManaged public var created_at: Date?
    @NSManaged public var updated_at: Date?
    @NSManaged public var actor_user_id: String?
    @NSManaged public var actor_device_id: String?
    @NSManaged public var source: String?
    @NSManaged public var operation_id: UUID?
    @NSManaged public var medicine: Medicine?
    @NSManaged public var attachments: Set<MedicineCommentAttachment>?
}

extension MedicineComment {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MedicineComment> {
        NSFetchRequest<MedicineComment>(entityName: "MedicineComment")
    }

    static func fetchRequest(for medicine: Medicine) -> NSFetchRequest<MedicineComment> {
        let request = MedicineComment.fetchRequest() as! NSFetchRequest<MedicineComment>
        request.predicate = NSPredicate(format: "medicine == %@", medicine)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        return request
    }
}
