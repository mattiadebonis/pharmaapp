//
//  DoseEventRecord.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import Foundation
import CoreData

@objc(DoseEvent)
public class DoseEventRecord: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var due_at: Date?
    @NSManaged public var status: String?
    @NSManaged public var created_at: Date?
    @NSManaged public var updated_at: Date?
    @NSManaged public var actor_user_id: String?
    @NSManaged public var actor_device_id: String?
    @NSManaged public var medicine: Medicine?
    @NSManaged public var therapy: Therapy?
}

extension DoseEventRecord {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DoseEventRecord> {
        NSFetchRequest<DoseEventRecord>(entityName: "DoseEvent")
    }

    enum Status: String {
        case planned
        case taken
        case missed
        case skipped
    }

    var statusValue: Status {
        Status(rawValue: status ?? "") ?? .planned
    }

    static func fetchRequest(for therapy: Therapy) -> NSFetchRequest<DoseEventRecord> {
        let request = DoseEventRecord.fetchRequest() as! NSFetchRequest<DoseEventRecord>
        request.predicate = NSPredicate(format: "therapy == %@", therapy)
        request.sortDescriptors = [NSSortDescriptor(key: "due_at", ascending: true)]
        return request
    }
}
