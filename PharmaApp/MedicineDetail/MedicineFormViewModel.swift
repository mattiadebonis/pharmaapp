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
            // Non creare automaticamente una Therapy: l'acquisto scorte non implica una pianificazione
            
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
    
    func addNewPrescriptionRequest(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, for: nil, type: "new_prescription_request")
    }
    
    func addNewPrescription(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, for: nil, type: "new_prescription")
    }
    
    func addPurchase(for medicine: Medicine, for package: Package) {
        addLog(for: medicine, for: package, for: nil, type: "purchase")
    }

    func addIntake(for medicine: Medicine, for package: Package, for therapy: Therapy) {
        addLog(for: medicine, for: package, for: therapy ,type: "intake")
    }

    func setStockUnits(medicine: Medicine, package: Package, targetUnits: Int) {
        let current = Self.currentUnits(for: medicine)
        let desired = max(0, targetUnits)
        let delta = desired - current
        guard delta != 0 else { return }
        let packSize = max(1, Int(package.numero))

        if delta > 0 {
            let purchaseCount = (delta + packSize - 1) / packSize
            for _ in 0..<purchaseCount {
                addLog(for: medicine, for: package, for: nil, type: "purchase")
            }
            let overshoot = purchaseCount * packSize - delta
            if overshoot > 0 {
                for _ in 0..<overshoot {
                    addLog(for: medicine, for: package, for: nil, type: "intake")
                }
            }
        } else {
            for _ in 0..<abs(delta) {
                addLog(for: medicine, for: package, for: nil, type: "intake")
            }
        }

        do {
            try context.save()
            DispatchQueue.main.async {
                self.isDataUpdated = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func addLog(for medicine: Medicine, for package: Package, for therapy: Therapy?, type: String) {
        let newLog = Log(context: context)
        newLog.id = UUID()
        newLog.type = type
        newLog.timestamp = Date()
        newLog.medicine = medicine
        newLog.package = package
        newLog.therapy = therapy
        do {
            try context.save()
            successMessage = "Log salvato: \(type)"
                    print("salvato")

        } catch {
            errorMessage = "Errore nel salvataggio del log: \(error.localizedDescription)"
        }
    }

    private static func currentUnits(for medicine: Medicine) -> Int {
        if let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty {
            return therapies.reduce(0) { $0 + Int($1.leftover()) }
        }
        return medicine.remainingUnitsWithoutTherapy() ?? 0
    }
}
