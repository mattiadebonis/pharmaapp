//
//  TherapyFormViewModel.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import Foundation
import CoreData
import SwiftUI

struct DoseEntry: Identifiable, Hashable {
    var id: UUID = UUID()
    var time: Date
    var amount: Double

    init(id: UUID = UUID(), time: Date, amount: Double) {
        self.id = id
        self.time = time
        self.amount = amount
    }
}

extension DoseEntry {
    static func fromDose(_ dose: Dose) -> DoseEntry {
        DoseEntry(time: dose.time, amount: dose.amountValue)
    }
}

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
        cycleOnDays: Int?,
        cycleOffDays: Int?,
        startDate: Date,
        doses: [DoseEntry],
        package: Package,
        medicinePackage: MedicinePackage?,
        importance: String,
        person: Person,
        condition: String?,
        manualIntake: Bool,
        notificationsSilenced: Bool,
        notificationLevel: TherapyNotificationLevel = .normal,
        snoozeMinutes: Int = 10,
        clinicalRules: ClinicalRules?
    ) {
        // Creazione di una nuova Therapy senza effettuare il fetch di una già esistente
        guard let therapyEntity = NSEntityDescription.entity(forEntityName: "Therapy", in: context) else {
            errorMessage = "Errore durante il salvataggio: entità Therapy non disponibile."
            return
        }
        let therapy = Therapy(entity: therapyEntity, insertInto: context)
        therapy.id = UUID()
        therapy.medicine = medicine
        therapy.package = package
        therapy.medicinePackage = medicinePackage
        therapy.importance = importance
        therapy.person = person  // associa la persona
        therapy.condizione = normalizedCondition(from: condition)
        therapy.manual_intake_registration = manualIntake
        therapy.notifications_silenced = notificationsSilenced
        therapy.notification_level = notificationLevel.rawValue
        therapy.snooze_minutes = Int32(snoozeMinutes)
        therapy.clinicalRulesValue = clinicalRules

        var rule = RecurrenceRule(freq: freq ?? "DAILY")
        rule.interval = interval ?? 1
        rule.until = until
        rule.count = count
        rule.byDay = byDay
        rule.cycleOnDays = cycleOnDays
        rule.cycleOffDays = cycleOffDays

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

        for entry in doses {
            guard let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
                errorMessage = "Errore durante il salvataggio: entità Dose non disponibile."
                return
            }
            let dose = Dose(entity: doseEntity, insertInto: context)
            dose.id = UUID()
            dose.time = entry.time
            dose.amount = NSNumber(value: entry.amount)
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
        cycleOnDays: Int?,
        cycleOffDays: Int?,
        startDate: Date,
        doses: [DoseEntry],
        package: Package,
        medicinePackage: MedicinePackage?,
        importance: String,
        person: Person,
        condition: String?,
        manualIntake: Bool,
        notificationsSilenced: Bool,
        notificationLevel: TherapyNotificationLevel = .normal,
        snoozeMinutes: Int = 10,
        clinicalRules: ClinicalRules?
    ) {
        therapy.importance = importance
        therapy.package = package
        if let medicinePackage {
            therapy.medicinePackage = medicinePackage
        }
        therapy.person = person  // aggiorna la persona
        therapy.condizione = normalizedCondition(from: condition)
        therapy.manual_intake_registration = manualIntake
        therapy.notifications_silenced = notificationsSilenced
        therapy.notification_level = notificationLevel.rawValue
        therapy.snooze_minutes = Int32(snoozeMinutes)
        therapy.clinicalRulesValue = clinicalRules
        
        var rule = RecurrenceRule(freq: freq ?? "DAILY")
        rule.interval = interval ?? 1
        rule.until = until
        rule.count = count
        rule.byDay = byDay
        rule.cycleOnDays = cycleOnDays
        rule.cycleOffDays = cycleOffDays
        
        let icsString = RecurrenceManager(context: context).buildRecurrenceString(from: rule)
        therapy.rrule = icsString
        therapy.setValue(startDate, forKey: "start_date")
        
        if let oldDoses = therapy.doses as? Set<Dose> {
            for dose in oldDoses {
                context.delete(dose)
            }
        }
        
        for entry in doses {
            guard let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
                errorMessage = "Errore durante l'aggiornamento: entità Dose non disponibile."
                return
            }
            let dose = Dose(entity: doseEntity, insertInto: context)
            dose.id = UUID()
            dose.time = entry.time
            dose.amount = NSNumber(value: entry.amount)
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

    func deleteTherapy(_ therapy: Therapy) {
        let doseEventsRequest = DoseEventRecord.fetchRequest(for: therapy)
        let measurementsRequest = MonitoringMeasurement.fetchRequest() as NSFetchRequest<MonitoringMeasurement>
        measurementsRequest.predicate = NSPredicate(format: "therapy == %@", therapy)
        let logsRequest = Log.fetchRequest() as! NSFetchRequest<Log>
        logsRequest.predicate = NSPredicate(format: "therapy == %@", therapy)

        do {
            let doseEvents = try context.fetch(doseEventsRequest)
            let measurements = try context.fetch(measurementsRequest)
            let logs = try context.fetch(logsRequest)

            if let doses = therapy.doses as? Set<Dose> {
                for dose in doses {
                    context.delete(dose)
                }
            }

            for doseEvent in doseEvents {
                context.delete(doseEvent)
            }

            for measurement in measurements {
                context.delete(measurement)
            }

            for log in logs {
                log.therapy = nil
            }

            context.delete(therapy)
            try context.save()
            successMessage = "Terapia eliminata!"
            DispatchQueue.main.async {
                self.isDataUpdated = true
            }
        } catch {
            errorMessage = "Errore durante l'eliminazione: \(error.localizedDescription)"
            print("Errore eliminazione Therapy: \(error.localizedDescription)")
        }
    }

    private func normalizedCondition(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
