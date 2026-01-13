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
            let stockService = StockService(context: context)
            _ = stockService.createLog(
                type: "purchase",
                medicine: medicine,
                package: package,
                save: false
            )
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
        let stockService = StockService(context: context)
        for _ in 0..<count {
            _ = stockService.createLog(
                type: "purchase",
                medicine: medicine,
                package: package,
                save: false
            )
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
        let stockService = StockService(context: context)

        if delta > 0 {
            let fullPackages = delta / packSize
            let remainingUnits = delta % packSize

            for _ in 0..<fullPackages {
                _ = stockService.createLog(
                    type: "purchase",
                    medicine: medicine,
                    package: package,
                    save: false
                )
            }

            if remainingUnits > 0 {
                for _ in 0..<remainingUnits {
                    _ = stockService.createLog(
                        type: "stock_increment",
                        medicine: medicine,
                        package: package,
                        save: false
                    )
                }
            }
        } else {
            for _ in 0..<abs(delta) {
                _ = stockService.createLog(
                    type: "stock_adjustment",
                    medicine: medicine,
                    package: package,
                    save: false
                )
            }
        }
        stockService.setUnits(desired, for: package)

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
        let stockService = StockService(context: context)
        _ = stockService.createLog(
            type: type,
            medicine: medicine,
            package: package,
            therapy: therapy,
            save: false
        )
        do {
            try context.save()
            successMessage = "Log salvato: \(type)"
                    print("salvato")

        } catch {
            errorMessage = "Errore nel salvataggio del log: \(error.localizedDescription)"
        }
    }

    private static func currentUnits(for medicine: Medicine, package: Package) -> Int {
        guard let context = medicine.managedObjectContext ?? package.managedObjectContext else { return 0 }
        let stockService = StockService(context: context)
        return max(0, stockService.units(for: package))
    }
}
