//
//  Stock.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 19/02/25.
//

import CoreData

@objc(Stock)
public class Stock: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var stock_units: Int32
    @NSManaged public var context_key: String
    @NSManaged public var updated_at: Date
    @NSManaged public var medicine: Medicine
    @NSManaged public var package: Package
}

extension Stock {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Stock> {
        NSFetchRequest<Stock>(entityName: "Stock")
    }

    static func fetchRequest(package: Package, contextKey: String) -> NSFetchRequest<Stock> {
        let request: NSFetchRequest<Stock> = Stock.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "package == %@ AND context_key == %@", package, contextKey)
        return request
    }

    static func fetchRequest(medicine: Medicine, contextKey: String) -> NSFetchRequest<Stock> {
        let request: NSFetchRequest<Stock> = Stock.fetchRequest()
        request.predicate = NSPredicate(format: "medicine == %@ AND context_key == %@", medicine, contextKey)
        return request
    }
}
