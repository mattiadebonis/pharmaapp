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
        // Recuperiamo i log relativi a questo package
        guard let allLogs = medicine.logs else { return 0 }
        let relevantLogs = allLogs.filter { $0.package == self.package }
        
        // Quanti acquisti e quante assunzioni
        let purchaseCount = relevantLogs.filter { $0.type == "purchase" }.count
        let intakeCount   = relevantLogs.filter { $0.type == "intake" }.count
        
        // Quante unità contiene *ognuna* di queste confezioni?
        let confezioneValore = package.numero
        
        // Scorte = (#purchase - #intake) * confezioneValore
        return (Int32(purchaseCount) * confezioneValore) - Int32(intakeCount)
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