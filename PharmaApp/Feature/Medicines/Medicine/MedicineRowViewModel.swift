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
    private let recurrenceManager = RecurrenceManager.shared
    private let operationIdProvider: OperationIdProviding

    init(
        managedObjectContext: NSManagedObjectContext,
        operationIdProvider: OperationIdProviding = OperationIdProvider.shared
    ) {
        self.managedObjectContext = managedObjectContext
        self.operationIdProvider = operationIdProvider
    }
    
    /// Funzione generica per salvare un log per una determinata medicina e tipo
    func addLog(
        for medicine: Medicine,
        type: String,
        package: Package? = nil,
        therapy: Therapy? = nil,
        operationId: UUID? = nil
    ) {
        let resolvedPackage = resolvePackage(for: medicine, fallback: package, therapy: therapy)
        let stockService = StockService(context: managedObjectContext)
        let key = OperationKey.medicineAction(
            action: actionType(for: type),
            medicineId: medicine.id,
            packageId: resolvedPackage?.id,
            source: .medicineRow
        )
        let resolvedOperationId = operationId ?? operationIdProvider.operationId(for: key, ttl: 3)
        _ = stockService.createLog(
            type: type,
            medicine: medicine,
            package: resolvedPackage,
            therapy: therapy,
            operationId: resolvedOperationId,
            save: false
        )

        do {
            try managedObjectContext.save()
            print("Log salvato: \(type) per \(medicine.nome)")
            scheduleOperationClear(for: key)
        } catch {
            managedObjectContext.rollback()
            print("Errore nel salvataggio del log: \(error)")
            operationIdProvider.clear(key)
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
                    addLog(
                        for: medicine,
                        type: "stock_adjustment",
                        package: t.package,
                        operationId: operationIdProvider.newOperationId()
                    )
                }
            }
            return
        }
        // Caso senza terapie: usa remainingUnitsWithoutTherapy
        if let remaining = medicine.remainingUnitsWithoutTherapy(), remaining > 0 {
            let pkg = (medicine.packages.first) ?? getLastPurchasedPackage(for: medicine)
            for _ in 0..<remaining {
                addLog(
                    for: medicine,
                    type: "stock_adjustment",
                    package: pkg,
                    operationId: operationIdProvider.newOperationId()
                )
            }
        }
    }

    private func getLastPurchasedPackage(for medicine: Medicine) -> Package? {
        let logs = medicine.effectivePurchaseLogs()
        return logs
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first?.package
    }

    private func resolvePackage(for medicine: Medicine, fallback: Package?, therapy: Therapy?) -> Package? {
        if let fallback { return fallback }
        if let therapy { return therapy.package }
        if let lastPurchased = getLastPurchasedPackage(for: medicine) { return lastPurchased }
        if !medicine.packages.isEmpty {
            return medicine.packages.sorted(by: { $0.numero > $1.numero }).first
        }
        return nil
    }

    private func actionType(for logType: String) -> OperationAction {
        switch logType {
        case "purchase":
            return .purchase
        case "new_prescription_request":
            return .prescriptionRequest
        case "new_prescription":
            return .prescriptionReceived
        case "stock_adjustment":
            return .stockAdjustment
        default:
            return .intake
        }
    }

    private func scheduleOperationClear(for key: OperationKey, delay: TimeInterval = 2.4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.operationIdProvider.clear(key)
        }
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
