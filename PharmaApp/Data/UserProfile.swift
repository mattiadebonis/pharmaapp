//
//  UserProfile.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import Foundation
import CoreData

@objc(UserProfile)
public class UserProfile: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var user_id: String?
    @NSManaged public var display_name: String?
    @NSManaged public var device_id: String?
    @NSManaged public var created_at: Date?
}

extension UserProfile {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserProfile> {
        NSFetchRequest<UserProfile>(entityName: "UserProfile")
    }

    static func fetchRequest(for userId: String) -> NSFetchRequest<UserProfile> {
        let request = UserProfile.fetchRequest() as! NSFetchRequest<UserProfile>
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "user_id == %@", userId)
        return request
    }
}
