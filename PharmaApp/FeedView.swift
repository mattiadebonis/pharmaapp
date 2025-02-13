//
//  FeedView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 02/01/25.
//

import SwiftUI
import CoreData

struct FeedView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Medicine.extractMedicinesWithTherapiesOrPurchaseLogs())
    var medicines: FetchedResults<Medicine>
    
    @State private var dataUpdated = UUID()  
    @State private var selectedMedicine: Medicine? = nil  // Variabile per tenere traccia della medicine selezionata

    var body: some View {
        let medicineArray = Array(medicines)
        let sortedByWeight = medicineArray.sorted { $0.weight > $1.weight }
        
        VStack {
            ForEach(sortedByWeight) { medicine in
                MedicineRowView(medicine: medicine)
                    .contentShape(Rectangle()) // Assicura che l'intera area della riga sia tappabile
                    .onTapGesture {
                        selectedMedicine = medicine
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("dataDidChange"))) { _ in
            dataUpdated = UUID()
        }
        .id(dataUpdated)
        .sheet(item: $selectedMedicine) { medicine in
            MedicineDetailView(
                medicine: medicine,
                package: getPackage(for: medicine)
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible) 
        }
    }

    func getPackage(for medicine: Medicine) -> Package {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        } else if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            let sortedLogs = purchaseLogs.sorted { $0.timestamp > $1.timestamp }
            if let package = sortedLogs.first?.package {
                return package
            }
        }
        fatalError("Nessun package disponibile per \(medicine.nome ?? "medicine senza nome")")
    }
}
