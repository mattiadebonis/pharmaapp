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
    func addLog(for medicine: Medicine, type: String) {
        let newLog = Log(context: managedObjectContext)
        newLog.id = UUID()
        newLog.type = type
        newLog.timestamp = Date()
        newLog.medicine = medicine
        
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
    
    func addPurchase(for medicine: Medicine) {
        addLog(for: medicine, type: "purchase")
    }

    func prescriptionStatus(medicine : Medicine, currentOption : Option) -> String? {
        guard medicine.obbligo_ricetta else { return nil }
        let inEsaurimento = medicine.isInEsaurimento(option: currentOption, recurrenceManager: recurrenceManager)
        guard inEsaurimento else { return nil }
        
        if medicine.hasPendingNewPrescription() {
            return "Comprato"
        } else if medicine.hasNewPrescritpionRequest() {
            return "Ricetta arrivata"
        } else {
            return "Ricetta richiesta"
        }
    }
    
    @ViewBuilder
    func actionButton(for status: String, medicine: Medicine) -> some View {
        switch status {
        case "Ricetta richiesta":
            Button(action: {
                self.addNewPrescriptionRequest(for: medicine)
            }) {
                Text("Ricetta richiesta")
            }
        case "Ricetta arrivata":
            Button(action: {
                self.addNewPrescription(for: medicine)
            }) {
                Text("Ricetta arrivata")
            }
        case "Comprato":
            Button(action: {
                self.addPurchase(for: medicine)
            }) {
                Text("Comprato")
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
