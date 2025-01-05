//
//  MedicineFormViewModel.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import Foundation
import CoreData
import SwiftUI

class MedicineFormViewModel: ObservableObject {
    
    @Published var isDataUpdated: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var time: String = ""
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchTherapy(for medicine: Medicine) -> Therapy? {
        let fetchRequest = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        fetchRequest.predicate = NSPredicate(format: "medicine == %@", medicine)
        fetchRequest.fetchLimit = 1
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.first
        } catch {
            print("Errore fetch Therapy: \(error.localizedDescription)")
            return nil
        }
    }

    func saveForniture(medicine: Medicine){  
        do{
            let log = Log(context: context)
            log.id = UUID()
            log.timestamp = Date()
            log.medicine = medicine
            log.type = "purchase"
            
            try context.save()
            successMessage = "Salvataggio scorte riuscito!"

            DispatchQueue.main.async {
                self.isDataUpdated = true
            }

        } catch {
            print("Errore nel salvataggio di Furniture: \(error.localizedDescription)")
        }
        
    }

    func saveTherapy(
        medicine: Medicine,
        freq: String?,
        interval: Int?,
        until: Date?,
        count: Int?,
        byDay: [String],
        startDate: Date
    ) {
        let fetchRequest = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        fetchRequest.predicate = NSPredicate(format: "medicine == %@", medicine)
        fetchRequest.fetchLimit = 1
        
        do {
            let results = try context.fetch(fetchRequest)
            let therapy: Therapy
            if let existingTherapy = results.first {
                therapy = existingTherapy
            } else {
                therapy = Therapy(context: context)
                therapy.id = UUID()
                therapy.medicine = medicine
            }
            
            var rule = RecurrenceRule(freq: freq ?? "DAILY")
            rule.interval = interval ?? 1
            rule.until = until
            rule.count = count
            rule.byDay = byDay
            
            let icsString = RecurrenceManager(context: context)
                .buildRecurrenceString(from: rule)
            
            therapy.rrule = icsString
            therapy.setValue(startDate, forKey: "start_date")
            
            try context.save()
            successMessage = "Salvataggio riuscito!"

            DispatchQueue.main.async {
                self.isDataUpdated = true
            }
            
        } catch {
            errorMessage = "Errore durante il salvataggio: \(error.localizedDescription)"
            print("Errore nel salvataggio di Therapy: \(error.localizedDescription)")
        }
    }

    
}