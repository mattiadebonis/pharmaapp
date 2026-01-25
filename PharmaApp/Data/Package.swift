//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

import CoreData

@objc(Package)
public class Package: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var numero: Int32
    @NSManaged public var tipologia: String
    @NSManaged public var valore: Int32
    @NSManaged public var unita: String
    @NSManaged public var volume: String
    @NSManaged public var medicine: Medicine
    @NSManaged public var therapies: Set<Therapy>?
    @NSManaged public var stocks: Set<Stock>?
    @NSManaged public var medicinePackages: Set<MedicinePackage>?
    @NSManaged public var logs: Set<Log>?
}

extension Package{
    static func extractPackages() -> NSFetchRequest<Package> {
    
        let request:NSFetchRequest<Package> = Package.fetchRequest() as! NSFetchRequest <Package>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        
        request.sortDescriptors = [sortDescriptor]
        
        return request

    }

    func addToStocks(_ stock: Stock) {
        self.mutableSetValue(forKey: "stocks").add(stock)
    }
}
