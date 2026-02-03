//
//  Option.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 23/01/25.
//

import Foundation
import CoreData

@objc(Option)
public class Option: NSManagedObject, Identifiable {

    @NSManaged public var id: UUID
    @NSManaged public var manual_intake_registration: Bool
    @NSManaged public var day_threeshold_stocks_alarm: Int32

}

extension Option{
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Option> {
        return NSFetchRequest<Option>(entityName: "Option")
    }
    static func extractOptions() -> NSFetchRequest<Option> {
        let request:NSFetchRequest<Option> = Option.fetchRequest() as! NSFetchRequest <Option>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)    
        request.sortDescriptors = [sortDescriptor]
        return request
    }

    static func current(in context: NSManagedObjectContext?) -> Option? {
        guard let context else { return nil }
        let request = extractOptions()
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }
    
}
