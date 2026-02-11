//
//  NotificationSettings.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import Foundation
import CoreData

@objc(NotificationSettings)
public class NotificationSettings: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var user_id: String?
    @NSManaged public var grace_minutes: Int32
    @NSManaged public var notify_caregivers: Bool
    @NSManaged public var notify_shared: Bool
    @NSManaged public var updated_at: Date?
}

extension NotificationSettings {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NotificationSettings> {
        NSFetchRequest<NotificationSettings>(entityName: "NotificationSettings")
    }

    static func fetchRequest(for userId: String) -> NSFetchRequest<NotificationSettings> {
        let request = NotificationSettings.fetchRequest() as! NSFetchRequest<NotificationSettings>
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "user_id == %@", userId)
        return request
    }
}
