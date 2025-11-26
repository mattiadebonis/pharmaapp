//
//  Doctor.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 04/02/25.
//

import Foundation
import CoreData


@objc(Doctor)
public class Doctor: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var nome: String?
    @NSManaged public var cognome: String?
    @NSManaged public var mail: String?
    @NSManaged public var telefono: String?
    @NSManaged public var indirizzo: String?
    @NSManaged public var orari: String?
    @NSManaged public var medicines: Set<Medicine>?
   
}

extension Doctor {
    
    static func extractDoctors() -> NSFetchRequest<Doctor> {
        let request: NSFetchRequest<Doctor> = Doctor.fetchRequest() as! NSFetchRequest<Doctor>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }
}
