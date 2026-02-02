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
    @NSManaged public var codice_forma_dosaggio: String?
    @NSManaged public var principi_attivi_it_json: String?
    @NSManaged public var vie_somministrazione_json: String?
    @NSManaged public var codice_atc_json: String?
    @NSManaged public var descrizione_atc_json: String?
    @NSManaged public var forma_farmaceutica: String?
    @NSManaged public var piano_terapeutico: Int32
    @NSManaged public var descrizione_forma_dosaggio: String?
    @NSManaged public var flag_alcol: Bool
    @NSManaged public var flag_potassio: Bool
    @NSManaged public var flag_guida: Bool
    @NSManaged public var flag_dopante: Bool
    @NSManaged public var livello_guida: String?
    @NSManaged public var descrizione_livello: String?
    @NSManaged public var carente: Bool
    @NSManaged public var innovativo: Bool
    @NSManaged public var orfano: Bool
    @NSManaged public var revocato: Bool
    @NSManaged public var sospeso: Bool
    @NSManaged public var principio_attivo_forma_json: String?
    @NSManaged public var flag_fi: Bool
    @NSManaged public var flag_rcp: Bool
    @NSManaged public var tipo_autorizzazione: String?
    @NSManaged public var aic6_importazione_parallela: String?
    @NSManaged public var sis_importazione_parallela: String?
    @NSManaged public var den_importazione_parallela: String?
    @NSManaged public var rag_importazione_parallela: String?
    @NSManaged public var position_json: String?
    @NSManaged public var codice_medicinale: String?
    @NSManaged public var aic6: Int32
    @NSManaged public var denominazione_medicinale: String?
    @NSManaged public var codice_sis: Int32
    @NSManaged public var azienda_titolare: String?
    @NSManaged public var categoria_medicinale: Int32
    @NSManaged public var commercio: String?
    @NSManaged public var stato_amministrativo: String?
    @NSManaged public var custom_stock_threshold: Int32
    @NSManaged public var deadline_month: Int32
    @NSManaged public var deadline_year: Int32
    @NSManaged public var manual_intake_registration: Bool
    @NSManaged public var missed_dose_preset: String?
    @NSManaged public var safety_max_per_day: Int32
    @NSManaged public var safety_min_interval_hours: Int32
    @NSManaged public var in_cabinet: Bool
    @NSManaged public var prescribingDoctor: Doctor?
    @NSManaged public var therapies: Set<Therapy>?
    @NSManaged public var packages: Set<Package>
    @NSManaged public var stocks: Set<Stock>?
    @NSManaged public var logs: Set<Log>?
    @NSManaged public var todos: Set<Todo>?
    @NSManaged public var cabinet: Cabinet?
    @NSManaged public var medicinePackages: Set<MedicinePackage>?
    
    // MARK: - Relazioni di convenienza
    func addToTherapies(_ therapy: Therapy) {
        self.mutableSetValue(forKey: "therapies").add(therapy)
    }
    
    func addToLogs(_ log: Log) {
        self.mutableSetValue(forKey: "logs").add(log)
    }

    func addToTodos(_ todo: Todo) {
        self.mutableSetValue(forKey: "todos").add(todo)
    }
    
    func addToPackages(_ package: Package) {
        self.mutableSetValue(forKey: "packages").add(package)
    }

    func addToMedicinePackages(_ entry: MedicinePackage) {
        self.mutableSetValue(forKey: "medicinePackages").add(entry)
    }

    func addToStocks(_ stock: Stock) {
        self.mutableSetValue(forKey: "stocks").add(stock)
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

    /// Numero totale di unità disponibili quando la medicina non è legata a terapie.
    /// Usa il saldo persistito delle scorte (default context).
    func remainingUnitsWithoutTherapy() -> Int? {
        guard let context = managedObjectContext else { return 0 }
        let stockService = StockService(context: context)
        return stockService.units(for: self)
    }

    /// Restituisce `true` se esiste almeno un log di tipo "new_prescription"
    /// non seguito (cioè avvenuto dopo) da un log di tipo "purchase".
    func hasPendingNewPrescription() -> Bool {
        let newPrescriptionLogs = effectivePrescriptionReceivedLogs()
        if newPrescriptionLogs.isEmpty {
            return false
        }
        
        let purchaseLogs = effectivePurchaseLogs()
        
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
        let prescriptionLogs = effectivePrescriptionRequestLogs()
        guard !prescriptionLogs.isEmpty else { return false }
        
        // Trova l'ultimo log di "new_prescription" in base al timestamp
        guard let lastPrescription = prescriptionLogs.max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        
        // Filtra i log di tipo "purchase" che sono avvenuti dopo l'ultimo "new_prescription"
        let purchaseLogsAfterPrescription = effectivePurchaseLogs().filter { $0.timestamp > lastPrescription.timestamp }
        
        // Restituisce true solo se non sono stati trovati log di "purchase" successivi all'ultima "new_prescription"
        return purchaseLogsAfterPrescription.isEmpty
    }

    func hasEffectivePrescriptionReceived() -> Bool {
        !effectivePrescriptionReceivedLogs().isEmpty
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
    func hasIntakeToday(
        from date: Date = Date(),
        recurrenceManager: RecurrenceManager,
        calendar: Calendar = .current
    ) -> Bool {
        guard let therapies = therapies, !therapies.isEmpty else { return false }
        let today = calendar.startOfDay(for: date)
        return therapies.contains { therapy in
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? date
            let dosesPerDay = max(1, therapy.doses?.count ?? 1)
            return recurrenceManager.allowedEvents(
                on: today,
                rule: rule,
                startDate: start,
                dosesPerDay: dosesPerDay,
                calendar: calendar
            ) > 0
        }
    }

    /// True se esiste già un log di assunzione registrato nella giornata corrente.
    func hasIntakeLoggedToday(calendar: Calendar = .current) -> Bool {
        let todayLogs = effectiveIntakeLogs(on: Date(), calendar: calendar)
        return !todayLogs.isEmpty
    }

    func effectiveIntakeLogs(calendar: Calendar = .current) -> [Log] {
        effectiveLogs(type: "intake", undoType: "intake_undo")
    }

    func effectiveIntakeLogs(on date: Date, calendar: Calendar = .current) -> [Log] {
        effectiveIntakeLogs(calendar: calendar).filter { log in
            calendar.isDate(log.timestamp, inSameDayAs: date)
        }
    }

    func effectivePurchaseLogs() -> [Log] {
        effectiveLogs(type: "purchase", undoType: "purchase_undo")
    }

    func effectivePrescriptionRequestLogs() -> [Log] {
        effectiveLogs(type: "new_prescription_request", undoType: "prescription_request_undo")
    }

    func effectivePrescriptionReceivedLogs() -> [Log] {
        effectiveLogs(type: "new_prescription", undoType: "prescription_received_undo")
    }

    private func effectiveLogs(type: String, undoType: String) -> [Log] {
        let logs = Array(logs ?? [])
        guard !logs.isEmpty else { return [] }
        let reversed = reversedOperationIds(for: undoType, logs: logs)
        return logs.filter { log in
            guard log.type == type else { return false }
            guard let opId = log.operation_id else { return true }
            return !reversed.contains(opId)
        }
    }

    private func reversedOperationIds(for undoType: String, logs: [Log]) -> Set<UUID> {
        Set(
            logs.compactMap { log in
                guard log.type == undoType,
                      let opId = log.reversal_of_operation_id else {
                    return nil
                }
                return opId
            }
        )
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

    enum DeadlineStatus {
        case none
        case ok
        case expiringSoon
        case expired
    }

    var deadlineMonthYear: (month: Int, year: Int)? {
        guard let month = normalizedDeadlineMonth,
              let year = normalizedDeadlineYear else {
            return nil
        }
        return (month, year)
    }

    var deadlineLabel: String? {
        guard let info = deadlineMonthYear else { return nil }
        return String(format: "%02d/%04d", info.month, info.year)
    }

    var deadlineMonthStartDate: Date? {
        guard let info = deadlineMonthYear else { return nil }
        var comps = DateComponents()
        comps.year = info.year
        comps.month = info.month
        comps.day = 1
        return Calendar.current.date(from: comps)
    }

    var monthsUntilDeadline: Int? {
        guard let deadlineStart = deadlineMonthStartDate else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return calendar.dateComponents([.month], from: monthStart, to: deadlineStart).month
    }

    var deadlineStatus: DeadlineStatus {
        guard let months = monthsUntilDeadline else { return .none }
        if months < 0 { return .expired }
        if months <= 1 { return .expiringSoon }
        return .ok
    }

    func updateDeadline(month: Int?, year: Int?) {
        if let month, let year, isValidDeadline(month: month, year: year) {
            deadline_month = Int32(month)
            deadline_year = Int32(year)
        } else {
            deadline_month = 0
            deadline_year = 0
        }
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
        let prescriptionLogs = effectivePrescriptionReceivedLogs()
        // Se non ci sono ricette, non ha senso controllare gli acquisti
        guard let lastPrescription = prescriptionLogs.max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        
        let purchaseLogsAfterPrescription = effectivePurchaseLogs().filter { $0.timestamp > lastPrescription.timestamp }
        
        // Se non esistono acquisti dopo l'ultima ricetta, restituisce true
        return purchaseLogsAfterPrescription.isEmpty
    }
}

private extension Medicine {
    static let deadlineYearRange = 2000...2100

    var normalizedDeadlineMonth: Int? {
        let month = Int(deadline_month)
        return (1...12).contains(month) ? month : nil
    }

    var normalizedDeadlineYear: Int? {
        let year = Int(deadline_year)
        return Self.deadlineYearRange.contains(year) ? year : nil
    }

    func isValidDeadline(month: Int, year: Int) -> Bool {
        (1...12).contains(month) && Self.deadlineYearRange.contains(year)
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
