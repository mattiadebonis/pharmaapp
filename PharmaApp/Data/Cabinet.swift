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
    @NSManaged public var created_at: Date?
    @NSManaged public var id: UUID
    @NSManaged public var is_shared: Bool
    @NSManaged public var name: String
    @NSManaged public var medicines: Set<Medicine>
    @NSManaged public var medicinePackages: Set<MedicinePackage>?
    @NSManaged public var memberships: Set<CabinetMembership>?
    @NSManaged public var notificationLocks: Set<NotificationLock>?

}

extension Cabinet{
    static func extractCabinets() -> NSFetchRequest<Cabinet> {
        let request:NSFetchRequest<Cabinet> = Cabinet.fetchRequest() as! NSFetchRequest <Cabinet>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }

    private static let garassettoToken = "Garassetto"
    private static let nameTrimSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "-:"))

    var displayName: String {
        let raw = name.trimmingCharacters(in: Self.nameTrimSet)
        guard !raw.isEmpty else { return name }
        let cleaned = raw.replacingOccurrences(
            of: Self.garassettoToken,
            with: "",
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        let trimmed = cleaned.trimmingCharacters(in: Self.nameTrimSet)
        return trimmed.isEmpty ? raw : trimmed
    }
}
