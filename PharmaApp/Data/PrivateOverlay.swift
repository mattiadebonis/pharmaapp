//
//  PrivateOverlay.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import Foundation
import CoreData

@objc(PrivateOverlay)
public class PrivateOverlay: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var source_id: UUID?
    @NSManaged public var entity_type: String?
    @NSManaged public var notes: String?
    @NSManaged public var flags_json: String?
    @NSManaged public var created_at: Date?
    @NSManaged public var updated_at: Date?
}

extension PrivateOverlay {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PrivateOverlay> {
        NSFetchRequest<PrivateOverlay>(entityName: "PrivateOverlay")
    }

    static func fetchRequest(sourceId: UUID, entityType: String) -> NSFetchRequest<PrivateOverlay> {
        let request = PrivateOverlay.fetchRequest() as! NSFetchRequest<PrivateOverlay>
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "source_id == %@ AND entity_type == %@", sourceId as CVarArg, entityType)
        return request
    }
}
