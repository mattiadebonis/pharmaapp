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
        do {
            let log = Log(context: managedObjectContext)
            log.id = UUID()
            log.timestamp = Date()
            log.medicine = medicine
            log.type = "intake"

            try managedObjectContext.save()
        } catch {
            print("Error saving intake log: \(error.localizedDescription)")
        }
    }

    func calculateRemainingUnits() {
        if let package = medicine.packages.first {
            let purchaseLogs = fetchLogs(type: "purchase")
            let intakeLogs = fetchLogs(type: "intake")
            
            let totalNumberOfUnitsPurchased = Int(package.numero) * purchaseLogs
            let totalIntakes = intakeLogs
            
            totalNumberOfUnitsPurchasedPubli = totalNumberOfUnitsPurchased
            totalIntakesPubli = 

            self.remainingUnits = totalNumberOfUnitsPurchased - totalIntakes
            self.isAvailable = remainingUnits > 0
        }
    }

    private func fetchLogs(type: String) -> Int {
        let fetchRequest = NSFetchRequest<Log>(entityName: "Log")
        fetchRequest.predicate = NSPredicate(format: "type == %@ AND medicine == %@", type, medicine)

        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            return results.count
        } catch let error {
            print("Error fetching logs: \(error)")
            return 0
        }
    }
}