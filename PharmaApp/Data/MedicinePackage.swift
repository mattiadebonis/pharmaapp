//
//  MedicinePackage.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 24/01/26.
//

import Foundation
import CoreData

@objc(MedicinePackage)
public class MedicinePackage: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var created_at: Date?
    @NSManaged public var source_id: UUID?
    @NSManaged public var visibility: String?
    @NSManaged public var cabinet: Cabinet?
    @NSManaged public var medicine: Medicine
    @NSManaged public var package: Package
    @NSManaged public var therapies: Set<Therapy>?
}

extension MedicinePackage {
    static func extractEntries() -> NSFetchRequest<MedicinePackage> {
        let request: NSFetchRequest<MedicinePackage> = MedicinePackage.fetchRequest() as! NSFetchRequest<MedicinePackage>
        let sortDescriptor = NSSortDescriptor(key: "created_at", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }
}
