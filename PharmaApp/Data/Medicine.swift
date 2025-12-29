//
//  Medicine.swift
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
    @NSManaged public var custom_stock_threshold: Int32
    @NSManaged public var in_cabinet: Bool
    @NSManaged public var prescribingDoctor: Doctor?
    @NSManaged public var therapies: Set<Therapy>?
    @NSManaged public var packages: Set<Package>
    @NSManaged public var logs: Set<Log>?
    @NSManaged public var cabinet: Cabinet?
    
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
        return coverageDays < Double(stockThreshold(option: option))
    }

    /// Calcola il numero totale di unità disponibili quando la medicina non è legata a terapie.
    /// Somma tutte le confezioni acquistate (moltiplicando per `numero`) e sottrae le assunzioni.
    /// Restituisce `0` se non ci sono log associati.
    func remainingUnitsWithoutTherapy() -> Int? {
        let logs = self.logs ?? []
        if logs.isEmpty {
            return 0
        }
        var total = 0
        for log in logs {
            switch log.type {
            case "purchase":
                if let pkg = log.package {
                    total += Int(pkg.numero)
                }
            case "stock_increment":
                total += 1
            case "intake", "stock_adjustment":
                total -= 1
            default:
                continue
            }
        }
        return total
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

    /// Restituisce la prossima assunzione programmata a partire da `date`, calcolata sulle terapie e sulle regole di ricorrenza.
    func nextIntakeDate(from date: Date = Date(), recurrenceManager: RecurrenceManager) -> Date? {
        guard let therapies = therapies, !therapies.isEmpty else { return nil }
        let candidates: [Date] = therapies.compactMap { therapy in
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? date
            return recurrenceManager.nextOccurrence(
                rule: rule,
                startDate: start,
                after: date,
                doses: therapy.doses as NSSet?
            )
        }
        return candidates.sorted().first
    }

    /// True se esiste un'assunzione prevista oggi (a partire da `date`).
    func hasIntakeToday(from date: Date = Date(), recurrenceManager: RecurrenceManager) -> Bool {
        guard let next = nextIntakeDate(from: date, recurrenceManager: recurrenceManager) else { return false }
        return Calendar.current.isDateInToday(next)
    }

    /// True se esiste già un log di assunzione registrato nella giornata corrente.
    func hasIntakeLoggedToday(calendar: Calendar = .current) -> Bool {
        guard let logs = logs, !logs.isEmpty else { return false }
        return logs.contains { log in
            log.type == "intake" && calendar.isDateInToday(log.timestamp)
        }
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
    
    func stockThreshold(option: Option?) -> Int {
        let custom = Int(custom_stock_threshold)
        return custom > 0 ? custom : 7
    }
    
    
    /// Calcola il punteggio (score) per **una** Therapy, usando RecurrenceManager
    private func scoreForTherapy(_ therapy: Therapy, recurrenceManager: RecurrenceManager) -> Int {
        
        var score = 0
        
        let leftover = Double(therapy.leftover())
        let dailyUsage = therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        
        // A) Scorte / Coverage
        if leftover <= 0 {
            score += 60
        } else if dailyUsage > 0 {
            let coverageDays = leftover / dailyUsage
            
            switch coverageDays {
            case ..<0:
                score += 500
            case 0..<2:
                score += 60
            case 2..<4:
                score += 50
            case 4..<7:
                score += 40
            case 7..<14:
                score += 30
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
                score += 500
            case 0..<1:
                score += 60
            case 1..<3:
                score += 50
            case 3..<6:
                score += 40
            case 6..<12:
                score += 30
            case 12..<24:
                score += 20
            default:
                break
            }
        }
        
        // C) Importanza clinica
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

// MARK: - NUOVE PROPRIETÀ E FUNZIONI PER IL “SECONDO LAYER” DI ORDINAMENTO
extension Medicine {
    
    /// Data futura più vicina tra TUTTE le terapie di questa Medicine (se esiste).
    var earliestNextDoseDate: Date? {
        guard let allTherapies = therapies, !allTherapies.isEmpty else {
            return nil
        }
        
        var earliest: Date? = nil
        for therapy in allTherapies {
            if let nextDose = findNextDoseDate(for: therapy) {
                if earliest == nil || nextDose < earliest! {
                    earliest = nextDose
                }
            }
        }
        return earliest
    }
    
    /// Tempo (in secondi) da adesso alla dose futura più vicina.
    /// Se non c’è una prossima dose futura, restituisce un valore molto grande
    /// (in modo da finire “in fondo” all’ordinamento secondario).
    var earliestNextDoseInterval: TimeInterval {
        guard let nextDate = earliestNextDoseDate else {
            return TimeInterval.greatestFiniteMagnitude
        }
        return nextDate.timeIntervalSinceNow
    }
    
    /// Ritorna SOLO le medicine che hanno terapie o acquisti (purchase),
    /// ordinate dapprima per `weight` DESC, e a parità di `weight` per `earliestNextDoseDate` ASC.
    static func fetchAndSortByWeightThenNextDose() -> [Medicine] {
        let context = PersistenceController.shared.container.viewContext

        // 1) Costruiamo la fetchRequest di base
        let request: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>

        // 2) Eseguiamo la fetch senza filtrare: accogliamo anche medicine appena create
        do {
            let results = try context.fetch(request)
            
            // 3) Ordiniamo localmente con criteri multipli:
            //    - weight DESC
            //    - prossima dose ASC (nil in fondo)
            //    - nome ASC come fallback
            let sorted = results.sorted { m1, m2 in
                if m1.weight == m2.weight {
                    let next1 = m1.earliestNextDoseDate ?? .distantFuture
                    let next2 = m2.earliestNextDoseDate ?? .distantFuture
                    if next1 == next2 {
                        return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
                    }
                    return next1 < next2
                } else {
                    // Altrimenti, medicine con weight più alto prima
                    return m1.weight > m2.weight
                }
            }
            
            return sorted
        } catch {
            // In caso di errore, restituiamo un array vuoto
            return []
        }
}
}
