//
//  Dose.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 23/01/25.
//

import CoreData
import Foundation

@objc(Dose)
public class Dose: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var time: Date      // orario specifico
    @NSManaged public var therapy: Therapy
}



extension Dose{
    static func extractDoses() -> NSFetchRequest<Dose> {
    
        let request:NSFetchRequest<Dose> = Dose.fetchRequest() as! NSFetchRequest <Dose>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        
        request.sortDescriptors = [sortDescriptor]
        
        return request

    }
}

