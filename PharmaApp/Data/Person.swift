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
    @NSManaged public var codice_fiscale: String?
    @NSManaged public var is_account: Bool
    
    // Aggiunta relazione: una Persona può avere più Therapy
    @NSManaged public var therapies: Set<Therapy>?
  
}

extension Person {
    static func extractPersons(includeAccount: Bool = true) -> NSFetchRequest<Person> {
        let request: NSFetchRequest<Person> = Person.fetchRequest() as! NSFetchRequest<Person>
        if !includeAccount {
            request.predicate = NSPredicate(format: "is_account == NO")
        }
        let sortDescriptor = NSSortDescriptor(key: "nome", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }

    static func fetchAccountPerson() -> NSFetchRequest<Person> {
        let request = extractPersons(includeAccount: true)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "is_account == YES")
        return request
    }
}
