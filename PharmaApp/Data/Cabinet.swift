//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

import Foundation
import CoreData

@objc(Cabinet)
public class Cabinet : NSManagedObject , Identifiable{
    @NSManaged public var id : UUID
    @NSManaged public var name : String
    @NSManaged public var medicines: Set<Medicine>

}

extension Cabinet{
    static func extractCabinets() -> NSFetchRequest<Cabinet> {
        let request:NSFetchRequest<Cabinet> = Cabinet.fetchRequest() as! NSFetchRequest <Cabinet>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }
}
