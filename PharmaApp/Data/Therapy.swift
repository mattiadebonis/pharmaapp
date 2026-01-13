//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

import Foundation
import CoreData

@objc(Therapy)
public class Therapy: NSManagedObject, Identifiable {
    
    @NSManaged public var id: UUID
    @NSManaged public var medicine: Medicine
    @NSManaged public var start_date: Date?
    @NSManaged public var rrule: String?
    @NSManaged public var doses: Set<Dose>?
    @NSManaged public var package: Package
    @NSManaged public var importance: String?
    @NSManaged public var logs: Set<Log>?
    @NSManaged public var manual_intake_registration: Bool

    // Aggiunta relazione: ogni Therapy appartiene a una Person
    @NSManaged public var person: Person
}


extension Therapy {
    
    static let importanceValues = ["vital", "essential", "standard"]

    static func extractTherapies() -> NSFetchRequest<Therapy> {
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }
    
    func leftover() -> Int32 {
        guard let context = medicine.managedObjectContext ?? package.managedObjectContext else { return 0 }
        let stockService = StockService(context: context)
        return Int32(stockService.units(for: package))
    }

    /// Stima il consumo giornaliero in base a rrule e al numero di dosi (orari).
    func stimaConsumoGiornaliero(recurrenceManager: RecurrenceManager) -> Double {
        let rruleString = rrule ?? ""
        if rruleString.isEmpty { return 0 }
        
        // Parsing rrule
        let parsedRule = recurrenceManager.parseRecurrenceString(rruleString)
        let freq = parsedRule.freq.uppercased()   // "DAILY", "WEEKLY", etc.
        let interval = parsedRule.interval ?? 1
        let byDayCount = parsedRule.byDay.count
        let doseCount = doses?.count ?? 1
        
        switch freq {
        case "DAILY":
            // doseCount al giorno / interval
            // (es. interval=2 => doseCount / 2 al giorno)
            return Double(doseCount) / Double(interval)
            
        case "WEEKLY":
            // doseCount * byDayCount a settimana => / (7*interval)
            let settimanali = Double(doseCount * max(byDayCount, 1))
            let daily = settimanali / Double(7 * interval)
            return daily
            
        default:
            return 0
        }
    }
}
