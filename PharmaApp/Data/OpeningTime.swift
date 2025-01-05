//
//  OpeningTime.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 02/01/25.
//

import Foundation
import CoreData

@objc(OpeningTime)
public class OpeningTime: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var opening_time: String
    @NSManaged public var turno: Bool
    @NSManaged public var pharmacie: Pharmacie
}
