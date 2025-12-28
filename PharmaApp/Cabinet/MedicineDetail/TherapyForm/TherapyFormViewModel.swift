//
//  TherapyFormViewModel.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import Foundation
import CoreData
import SwiftUI

class TherapyFormViewModel: ObservableObject {
    
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


    func saveTherapy(
        medicine: Medicine,
        freq: String?,
        interval: Int?,    
        until: Date?,
        count: Int?,
        byDay: [String],
        startDate: Date,
        times: [Date],
        package: Package,
        importance: String,
        person: Person,
        manualIntake: Bool
    ) {
        // Creazione di una nuova Therapy senza effettuare il fetch di una già esistente
        let therapy = Therapy(context: context)
        therapy.id = UUID()
        therapy.medicine = medicine
        therapy.package = package
        therapy.importance = importance
        therapy.person = person  // associa la persona
        therapy.manual_intake_registration = manualIntake

        var rule = RecurrenceRule(freq: freq ?? "DAILY")
        rule.interval = interval ?? 1
        rule.until = until
        rule.count = count
        rule.byDay = byDay

        let icsString = RecurrenceManager(context: context)
            .buildRecurrenceString(from: rule)
        therapy.rrule = icsString
        therapy.setValue(startDate, forKey: "start_date")

        // Se esistono vecchie dosi, le eliminiamo
        if let oldDoses = therapy.doses as? Set<Dose> {
            for dose in oldDoses {
                context.delete(dose)
            }
        }

        for time in times {
            let dose = Dose(context: context)
            dose.id = UUID()
            dose.time = time
            dose.therapy = therapy  
        }

        do {
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

    // Nuovo metodo per aggiornare una Therapy esistente
    func updateTherapy(
        therapy: Therapy,
        freq: String?,
        interval: Int?,    
        until: Date?,
        count: Int?,
        byDay: [String],
        startDate: Date,
        times: [Date],
        package: Package,
        importance: String,
        person: Person,
        manualIntake: Bool
    ) {
        therapy.importance = importance
        therapy.package = package
        therapy.person = person  // aggiorna la persona
        therapy.manual_intake_registration = manualIntake
        
        var rule = RecurrenceRule(freq: freq ?? "DAILY")
        rule.interval = interval ?? 1
        rule.until = until
        rule.count = count
        rule.byDay = byDay
        
        let icsString = RecurrenceManager(context: context).buildRecurrenceString(from: rule)
        therapy.rrule = icsString
        therapy.setValue(startDate, forKey: "start_date")
        
        if let oldDoses = therapy.doses as? Set<Dose> {
            for dose in oldDoses {
                context.delete(dose)
            }
        }
        
        for time in times {
            let dose = Dose(context: context)
            dose.id = UUID()
            dose.time = time
            dose.therapy = therapy  
        }
        
        do {
            try context.save()
            successMessage = "Aggiornamento riuscito!"
            DispatchQueue.main.async {
                self.isDataUpdated = true
            }
        } catch {
            errorMessage = "Errore durante l'aggiornamento: \(error.localizedDescription)"
            print("Errore aggiornamento Therapy: \(error.localizedDescription)")
        }
    }
}
