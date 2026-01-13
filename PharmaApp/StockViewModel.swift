//
//  StockViewModel.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 05/01/25.
//

import CoreData

class StockRowViewModel: ObservableObject {
    @Published var remainingUnits = 0
    @Published var isAvailable = false


    @Published var totalNumberOfUnitsPurchasedPubli = 0
    @Published var totalIntakesPubli = 0
    
    private var managedObjectContext: NSManagedObjectContext
    var medicine: Medicine

    init(context: NSManagedObjectContext, medicine: Medicine) {
        self.managedObjectContext = context
        self.medicine = medicine
        calculateRemainingUnits()
    }

    func saveIntakeLog() {
        guard let package = resolvePackage(for: medicine) else { return }
        do {
            let stockService = StockService(context: managedObjectContext)
            _ = stockService.createLog(
                type: "intake",
                medicine: medicine,
                package: package,
                save: false
            )

            try managedObjectContext.save()
        } catch {
            print("Error saving intake log: \(error.localizedDescription)")
        }
    }

    func calculateRemainingUnits() {
        guard let package = resolvePackage(for: medicine) else {
            remainingUnits = 0
            isAvailable = false
            return
        }
        let stockService = StockService(context: managedObjectContext)
        let units = stockService.units(for: package)
        self.remainingUnits = units
        self.isAvailable = units > 0
    }

    private func resolvePackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        if let logs = medicine.logs {
            if let package = logs.filter({ $0.type == "purchase" })
                .sorted(by: { $0.timestamp > $1.timestamp })
                .first?.package {
                return package
            }
        }
        if !medicine.packages.isEmpty {
            return medicine.packages.sorted(by: { $0.numero > $1.numero }).first
        }
        return nil
    }
}
