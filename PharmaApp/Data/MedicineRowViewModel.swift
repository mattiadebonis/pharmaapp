//
//  SuppliesViewModel.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 04/02/25.
//

import SwiftUI
import CoreData

class MedicineRowViewModel: ObservableObject {
    let managedObjectContext: NSManagedObjectContext
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)

    init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }
    
    /// Funzione generica per salvare un log per una determinata medicina e tipo
    func addLog(for medicine: Medicine, type: String, package: Package? = nil, therapy: Therapy? = nil) {
        let newLog = Log(context: managedObjectContext)
        newLog.id = UUID()
        newLog.type = type
        newLog.timestamp = Date()
        newLog.medicine = medicine
        if let pkg = package { newLog.package = pkg }
        if let t = therapy { newLog.therapy = t }
        
        do {
            try managedObjectContext.save()
            print("Log salvato: \(type) per \(medicine.nome)")
        } catch {
            print("Errore nel salvataggio del log: \(error)")
        }
    }
    
    func addNewPrescriptionRequest(for medicine: Medicine) {
        addLog(for: medicine, type: "new_prescription_request")
    }
    
    func addNewPrescription(for medicine: Medicine) {
        addLog(for: medicine, type: "new_prescription")
    }
    
    func addPurchase(for medicine: Medicine, package: Package? = nil) {
        addLog(for: medicine, type: "purchase", package: package)
    }
    
    func addIntake(for medicine: Medicine, package: Package? = nil, therapy: Therapy? = nil) {
        addLog(for: medicine, type: "intake", package: package, therapy: therapy)
    }

    // Svuota tutte le scorte disponibili per la medicina, creando log di stock_adjustment
    func emptyStocks(for medicine: Medicine) {
        // Caso con terapie: svuota per ogni therapy sulla base del suo package
        if let therapies = medicine.therapies, !therapies.isEmpty {
            for t in therapies {
                let left = Int(max(0, t.leftover()))
                guard left > 0 else { continue }
                for _ in 0..<left {
                    addLog(for: medicine, type: "stock_adjustment", package: t.package)
                }
            }
            return
        }
        // Caso senza terapie: usa remainingUnitsWithoutTherapy
        if let remaining = medicine.remainingUnitsWithoutTherapy(), remaining > 0 {
            let pkg = (medicine.packages.first) ?? getLastPurchasedPackage(for: medicine)
            for _ in 0..<remaining {
                addLog(for: medicine, type: "stock_adjustment", package: pkg)
            }
        }
    }

    private func getLastPurchasedPackage(for medicine: Medicine) -> Package? {
        guard let logs = medicine.logs else { return nil }
        return logs.filter { $0.type == "purchase" }
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first?.package
    }

    func prescriptionStatus(medicine : Medicine, currentOption : Option) -> String? {
        guard medicine.obbligo_ricetta else { return nil }
        let inEsaurimento = medicine.isInEsaurimento(option: currentOption, recurrenceManager: recurrenceManager)
        guard inEsaurimento else { return nil }
        
        if medicine.hasPendingNewPrescription() {
            return "Compra"
        } else {
            return "Richiedi ricetta"
        }
    }
    
    @ViewBuilder
    func actionButton(for status: String, medicine: Medicine) -> some View {
        switch status {
        case "Richiedi ricetta":
            Button(action: {
                self.addNewPrescriptionRequest(for: medicine)
                self.addNewPrescription(for: medicine)
            }) {
                Text("Richiedi ricetta")
            }
        case "Compra":
            Button(action: {
                self.addPurchase(for: medicine)
            }) {
                Text("Compra")
            }
        default:
            EmptyView()
        }
    }

    private func recurrenceDescription(therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        return recurrenceManager.describeRecurrence(rule: rule)
    }
    
}
