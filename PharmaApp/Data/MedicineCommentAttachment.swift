import Foundation
import CoreData

@objc(MedicineCommentAttachment)
public final class MedicineCommentAttachment: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var kind: String?
    @NSManaged public var filename: String?
    @NSManaged public var mime_type: String?
    @NSManaged public var uti: String?
    @NSManaged public var byte_size: Int64
    @NSManaged public var relative_path: String?
    @NSManaged public var created_at: Date?
    @NSManaged public var comment: MedicineComment?
}

extension MedicineCommentAttachment {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MedicineCommentAttachment> {
        NSFetchRequest<MedicineCommentAttachment>(entityName: "MedicineCommentAttachment")
    }
}
