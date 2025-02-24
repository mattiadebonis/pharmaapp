//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

import Foundation
import CoreData

@objc(Medicine)
public class Medicine: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var nome: String
    @NSManaged public var principio_attivo: String
    @NSManaged public var obbligo_ricetta: Bool
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

    func isInEsaurimento(option: Option, recurrenceManager: RecurrenceManager) -> Bool {
        
        guard let therapies = self.therapies, !therapies.isEmpty else {
            return false
        }
        
        var totaleScorte: Double = 0
        var consumoGiornalieroTotale: Double = 0
        
        for therapy in therapies {
            let leftover = Double(therapy.leftover())
            totaleScorte += leftover
            let dailyUsage = therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            consumoGiornalieroTotale += dailyUsage
        }
        
        if totaleScorte <= 0 {
            return true
        }
        
        guard consumoGiornalieroTotale > 0 else {
            return false
        }
        
        let coverageDays = totaleScorte / consumoGiornalieroTotale
        return coverageDays < Double(option.day_threeshold_stocks_alarm)
    }

    /// Restituisce `true` se esiste almeno un log di tipo "new_prescription"
    /// non seguito (cioè avvenuto dopo) da un log di tipo "purchase".
    func hasPendingNewPrescription() -> Bool {
        // Se non ci sono log, ritorna false
        guard let logs = self.logs, !logs.isEmpty else { return false }
        
        // Filtra i log di tipo "new_prescription"
        let newPrescriptionLogs = logs.filter { $0.type == "new_prescription" }
        if newPrescriptionLogs.isEmpty {
            return false
        }
        
        // Filtra i log di tipo "purchase"
        let purchaseLogs = logs.filter { $0.type == "purchase" }
        
        // Trova l'ultimo log di "new_prescription" (in base al timestamp)
        guard let lastNewPrescription = newPrescriptionLogs.max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        
        // Trova l'ultimo log di "purchase", se esiste
        if let lastPurchase = purchaseLogs.max(by: { $0.timestamp < $1.timestamp }) {
            // Se l'ultimo log di new_prescription è più recente dell'ultimo purchase, allora c'è una prescrizione non seguita
            return lastNewPrescription.timestamp > lastPurchase.timestamp
        } else {
            // Se non esistono log di purchase, allora c'è almeno una new_prescription pendente
            return true
        }
    }

    func hasNewPrescritpionRequest() -> Bool {
        // Verifica che esistano log associati alla medicina
        guard let logs = self.logs, !logs.isEmpty else { return false }
        
        // Filtra i log di tipo "new_prescription"
        let prescriptionLogs = logs.filter { $0.type == "new_prescription_request" }
        guard !prescriptionLogs.isEmpty else { return false }
        
        // Trova l'ultimo log di "new_prescription" in base al timestamp
        guard let lastPrescription = prescriptionLogs.max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        
        // Filtra i log di tipo "purchase" che sono avvenuti dopo l'ultimo "new_prescription"
        let purchaseLogsAfterPrescription = logs.filter { $0.type == "purchase" && $0.timestamp > lastPrescription.timestamp }
        
        // Restituisce true solo se non sono stati trovati log di "purchase" successivi all'ultima "new_prescription"
        return purchaseLogsAfterPrescription.isEmpty
    }


    /// Calcolo di un punteggio complessivo ("weight") che deriva da:
    /// - Scorte rimanenti (coverage)
    /// - Imminenza prossima dose
    /// - Importanza clinica (therapy.importance: "vital", "essential", "standard")
    ///
    /// Per interpretare rrule, istanziamo e usiamo `RecurrenceManager`.
    var weight: Int {
        
        // Se non ci sono therapy, punteggio zero
        guard let allTherapies = therapies, !allTherapies.isEmpty else {
            return 0
        }
        
        // Recupera o crea un RecurrenceManager
        let recManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        
        var totalScore = 0
        
        // Per ogni therapy, calcoliamo un punteggio e sommiamo
        for therapy in allTherapies {
            totalScore += scoreForTherapy(therapy, recurrenceManager: recManager)
        }
        
        return totalScore
    }
    
    
    /// Calcola il punteggio (score) per **una** Therapy, usando RecurrenceManager
    private func scoreForTherapy(_ therapy: Therapy, recurrenceManager: RecurrenceManager) -> Int {
        
        var score = 0
        
        let leftover = Double(therapy.leftover())
        let dailyUsage = therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        
        if leftover <= 0 {
            score += 60
        } else if dailyUsage > 0 {
            let coverageDays = leftover / dailyUsage
            
            switch coverageDays {
            case ..<0:
                score += 60
            case 0..<2:
                score += 50
            case 2..<4:
                score += 40
            case 4..<7:
                score += 30
            case 7..<14:
                score += 20
            default:
                break
            }
        }
        
        // B) Prossima dose imminente
        if let nextDoseDate = findNextDoseDate(for: therapy) {
            let hoursToDose = nextDoseDate.timeIntervalSince(Date()) / 3600.0
            switch hoursToDose {
            case ..<0:
                // dose scaduta
                score += 60
            case 0..<1:
                score += 50
            case 1..<3:
                score += 40
            case 3..<6:
                score += 30
            case 6..<12:
                score += 20
            case 12..<24:
                score += 10
            default:
                break
            }
        }
        
        // C) Importanza clinica (sulla Therapy stessa)
        if let importance = therapy.importance {
            switch importance {
            case "vital":
                score += 40
            case "essential":
                score += 20
            default:
                // "standard"
                break
            }
        }
        
        return score
    }
    
    /// Trova l'orario più vicino (futuro) tra le doses di una Therapy
    private func findNextDoseDate(for therapy: Therapy) -> Date? {
        guard let dSet = therapy.doses else { return nil }
        
        let now = Date()
        // Filtra le date future
        let futureDoses = dSet.compactMap({ $0.time }).filter({ $0 > now })
        return futureDoses.min()
    }

    func isPrescriptionNotFollowedByPurchase() -> Bool {
        // Se non esistono log, restituisce false
        guard let logs = self.logs, !logs.isEmpty else { return false }
        
        // Filtra i log di tipo "new_prescription"
        let prescriptionLogs = logs.filter { $0.type == "new_prescription" }
        // Se non ci sono ricette, non ha senso controllare gli acquisti
        guard let lastPrescription = prescriptionLogs.max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        
        // Filtra i log di tipo "purchase" che sono avvenuti dopo l'ultima ricetta
        let purchaseLogsAfterPrescription = logs.filter { $0.type == "purchase" && $0.timestamp > lastPrescription.timestamp }
        
        // Se non esistono acquisti dopo l'ultima ricetta, restituisce true
        return purchaseLogsAfterPrescription.isEmpty
    }
}

