//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

import CoreData
import Foundation

@objc(Medicine)
public class Medicine: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var nome: String
    @NSManaged public var unita: String
    @NSManaged public var tipologia: String
    @NSManaged public var numero: Int32
    @NSManaged public var principio_attivo: String
    @NSManaged public var therapies: Set<Therapy>?
    @NSManaged public var packages: Set<Package>
    @NSManaged public var logs: Set<Log>?
    
    // MARK: - Relazioni di convenienza
    func addToTherapies(_ therapy: Therapy) {
        self.mutableSetValue(forKey: "therapies").add(therapy)
    }
    
    func addToLogs(_ log: Log) {
        self.mutableSetValue(forKey: "logs").add(log)
    }
    
    func addToPackages(_ package: Package) {
        self.mutableSetValue(forKey: "packages").add(package)
    }
}

extension Medicine {
    
    static func extractMedicines() -> NSFetchRequest<Medicine> {
        let request: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }
    
    static func extractMedicinesWithTherapiesOrPurchaseLogs() -> NSFetchRequest<Medicine> {
        let request: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        
        let therapiesPredicate = NSPredicate(format: "therapies.@count > 0")
        let purchasePredicate  = NSPredicate(format: "ANY logs.type == %@", "purchase")
        
        request.predicate = NSCompoundPredicate(
            orPredicateWithSubpredicates: [therapiesPredicate, purchasePredicate]
        )
        
        let sortDescriptor = NSSortDescriptor(key: "nome", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        
        return request
    }


    var weight: Int {
        var score = 0
        
        // +2 se ha almeno una therapy
        if (therapies?.count ?? 0) > 0 {
            score += 2
        }
        
        // +1 se ha almeno un log di tipo "purchase"
        if let logsSet = logs {
            // Conversione esplicita in array Swift
            let logArray = Array(logsSet)
            if logArray.contains(where: { $0.type == "purchase" }) {
                score += 1
            }
        }
        
        return score
    }
}

