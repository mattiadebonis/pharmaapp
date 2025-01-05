//
//  Pharmacie.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 02/01/25.
//

import Foundation
import CoreData

@objc(Pharmacie)
public class Pharmacie: NSManagedObject, Identifiable {
    @NSManaged public var id: Int16
    @NSManaged public var name: String
    @NSManaged public var phone: String
    @NSManaged public var address: String
    @NSManaged public var openingtimes: Set<OpeningTime>?

    func addToOpeningtimes(_ opening: OpeningTime) {
        self.mutableSetValue(forKey: "openingtimes").add(opening)
    }
}

extension Pharmacie {
    static func extractPharmacies() -> NSFetchRequest<Pharmacie> {
        let request: NSFetchRequest<Pharmacie> = Pharmacie.fetchRequest() as! NSFetchRequest<Pharmacie>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }
}
