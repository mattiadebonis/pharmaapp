//
//  Person.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 14/02/25.
//

import Foundation
import CoreData


@objc(Person)
public class Person: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var nome: String?
    @NSManaged public var cognome: String?
    
    // Aggiunta relazione: una Persona può avere più Therapy
    @NSManaged public var therapies: Set<Therapy>?
  
}

extension Person {
    
    static func extractPersons() -> NSFetchRequest<Person> {
        let request: NSFetchRequest<Person> = Person.fetchRequest() as! NSFetchRequest<Person>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }
}

