import Foundation
import CoreData
import SwiftUI

class MedicineFormViewModel: ObservableObject {
    
    @Published var isDataUpdated: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // Funzione esistente per salvare le scorte
    func saveForniture(medicine: Medicine, package: Package) {
        do {
            let log = Log(context: context)
            log.id = UUID()
            log.timestamp = Date()
            log.medicine = medicine
            log.package = package
            log.type = "purchase"
            
            // Se la medicine non ha terapie, puoi crearne una (opzionale)
            if medicine.therapies?.isEmpty ?? true {
                let therapy = Therapy(context: context)
                therapy.id = UUID()
                therapy.medicine = medicine
                therapy.rrule = nil
                therapy.start_date = nil
                therapy.package = package
            }
            
            try context.save()
            successMessage = "Salvataggio scorte riuscito!"
            DispatchQueue.main.async {
                self.isDataUpdated = true
            }
        } catch {
            print("Errore nel salvataggio di scorte: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Funzioni per la gestione della prescrizione
    
    func addNewPrescriptionRequest(for medicine: Medicine) {
        addLog(for: medicine, type: "new_prescription_request")
    }
    
    func addNewPrescription(for medicine: Medicine) {
        addLog(for: medicine, type: "new_prescription")
    }
    
    func addPurchase(for medicine: Medicine) {
        addLog(for: medicine, type: "purchase")
    }

    func addIntake(for medicine: Medicine) {
        addLog(for: medicine, type: "intake")
    }
    
    private func addLog(for medicine: Medicine, type: String) {
        let newLog = Log(context: context)
        newLog.id = UUID()
        newLog.type = type
        newLog.timestamp = Date()
        newLog.medicine = medicine
        // Se necessario, puoi associare anche il package qui
        do {
            try context.save()
            successMessage = "Log salvato: \(type)"
        } catch {
            errorMessage = "Errore nel salvataggio del log: \(error.localizedDescription)"
        }
    }
}
