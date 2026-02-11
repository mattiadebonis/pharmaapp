//
//  CabinetMembership.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import Foundation
import CoreData

@objc(CabinetMembership)
public class CabinetMembership: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var user_id: String?
    @NSManaged public var role: String?
    @NSManaged public var status: String?
    @NSManaged public var created_at: Date?
    @NSManaged public var cabinet: Cabinet?
}

extension CabinetMembership {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CabinetMembership> {
        NSFetchRequest<CabinetMembership>(entityName: "CabinetMembership")
    }

    static func fetchRequest(for cabinet: Cabinet) -> NSFetchRequest<CabinetMembership> {
        let request = CabinetMembership.fetchRequest() as! NSFetchRequest<CabinetMembership>
        request.predicate = NSPredicate(format: "cabinet == %@", cabinet)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        return request
    }
}
