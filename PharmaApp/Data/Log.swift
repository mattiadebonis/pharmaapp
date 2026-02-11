//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

import Foundation
import CoreData

@objc(Log)
public class Log : NSManagedObject , Identifiable{
    @NSManaged public var actor_device_id: String?
    @NSManaged public var actor_user_id: String?
    @NSManaged public var id: UUID
    @NSManaged public var operation_id: UUID?
    @NSManaged public var reversal_of_operation_id: UUID?
    @NSManaged public var source: String?
    @NSManaged public var synced_at: Date?
    @NSManaged public var type: String
    @NSManaged public var timestamp: Date
    @NSManaged public var medicine: Medicine
    @NSManaged public var therapy: Therapy?
    @NSManaged public var package: Package?
}

extension Log: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        self
    }
}

extension Log{
    static func extractLogs() -> NSFetchRequest<Log> {
        let request:NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest <Log>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }

    static func extractIntakeLogs() -> NSFetchRequest<Log> {
        let request:NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest <Log>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        request.predicate = NSPredicate(format: "type == 'intake'")
        return request
    }

    static func extractPurchaseLogs() -> NSFetchRequest<Log> {
        let request:NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest <Log>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        request.predicate = NSPredicate(format: "type == 'purchase'")
        return request
    }

    static func extractIntakeLogsFiltered(medicine: Medicine) -> NSFetchRequest<Log> {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.predicate = NSPredicate(format: "type == 'intake' AND medicine == %@", medicine)
        return request
    }

    static func extractPurchaseLogsFiltered(medicine: Medicine) -> NSFetchRequest<Log> {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.predicate = NSPredicate(format: "type == 'purchase' AND medicine == %@", medicine)
        return request
    }
}
