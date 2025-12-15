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

    func addPurchases(for medicine: Medicine, for package: Package, count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            let log = Log(context: context)
            log.id = UUID()
            log.type = "purchase"
            log.timestamp = Date()
            log.medicine = medicine
            log.package = package
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

    func addIntake(for medicine: Medicine, for package: Package, for therapy: Therapy) {
        addLog(for: medicine, for: package, for: therapy ,type: "intake")
    }

    func setStockUnits(medicine: Medicine, package: Package, targetUnits: Int) {
        let current = Self.currentUnits(for: medicine, package: package)
        let desired = max(0, targetUnits)
        let delta = desired - current
        guard delta != 0 else { return }
        let packSize = max(1, Int(package.numero))

        if delta > 0 {
            let fullPackages = delta / packSize
            let remainingUnits = delta % packSize

            for _ in 0..<fullPackages {
                let log = Log(context: context)
                log.id = UUID()
                log.type = "purchase"
                log.timestamp = Date()
                log.medicine = medicine
                log.package = package
            }

            if remainingUnits > 0 {
                for _ in 0..<remainingUnits {
                    let log = Log(context: context)
                    log.id = UUID()
                    log.type = "stock_increment"
                    log.timestamp = Date()
                    log.medicine = medicine
                    log.package = package
                }
            }
        } else {
            for _ in 0..<abs(delta) {
                let log = Log(context: context)
                log.id = UUID()
                log.type = "stock_adjustment"
                log.timestamp = Date()
                log.medicine = medicine
                log.package = package
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

    private static func currentUnits(for medicine: Medicine, package: Package) -> Int {
        let logs = medicine.logs ?? []
        let packSize = max(1, Int(package.numero))
        let matchesPackage: (Log) -> Bool = { log in
            if let pkg = log.package { return pkg == package }
            return medicine.packages.count == 1
        }
        let purchases = logs.filter { $0.type == "purchase" && matchesPackage($0) }.count
        let increments = logs.filter { $0.type == "stock_increment" && matchesPackage($0) }.count
        let decrements = logs.filter {
            ($0.type == "intake" || $0.type == "stock_adjustment") && matchesPackage($0)
        }.count
        return max(0, purchases * packSize + increments - decrements)
    }
}
