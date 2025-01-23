//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

import Foundation
import CoreData

@objc(Therapy)
public class Therapy : NSManagedObject , Identifiable{
    
    @NSManaged public var id : UUID
    @NSManaged public var medicine: Medicine
    @NSManaged public var start_date: Date?
    @NSManaged public var rrule: String?
    @NSManaged public var doses: Set<Dose>?
    @NSManaged public var package: Package
    
}


extension Therapy{
    static func extractTherapies() -> NSFetchRequest<Therapy> {
    
        let request:NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest <Therapy>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        
        request.sortDescriptors = [sortDescriptor]
        
        return request

    }
}

