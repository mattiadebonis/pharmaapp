//
//  NotificationLock.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import Foundation
import CoreData

@objc(NotificationLock)
public class NotificationLock: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var lock_key: String?
    @NSManaged public var expires_at: Date?
    @NSManaged public var created_at: Date?
    @NSManaged public var cabinet: Cabinet?
}

extension NotificationLock {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NotificationLock> {
        NSFetchRequest<NotificationLock>(entityName: "NotificationLock")
    }

    static func fetchRequest(for cabinet: Cabinet, lockKey: String) -> NSFetchRequest<NotificationLock> {
        let request = NotificationLock.fetchRequest() as! NSFetchRequest<NotificationLock>
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "cabinet == %@ AND lock_key == %@", cabinet, lockKey)
        return request
    }
}
