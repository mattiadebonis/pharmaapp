//
//  FeedView.swift
//  PharmaApp
//
//  Created by Mattia De Bonis on 02/01/25.
//

import SwiftUI
import CoreData

struct FeedView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Medicine.extractMedicinesWithTherapiesOrPurchaseLogs())
    var medicines: FetchedResults<Medicine>
    
    @ObservedObject var viewModel: FeedViewModel
    @State private var selectedMedicine: Medicine?

    var body: some View {
        let medicineArray = Array(medicines)
        let sortedByWeight = Medicine.fetchAndSortByWeightThenNextDose()

        VStack {
            ScrollView {
                VStack {
                    ForEach(sortedByWeight) { medicine in
                        MedicineRowView(
                            medicine: medicine,
                            isSelected: viewModel.isSelecting && viewModel.selectedMedicines.contains(medicine), // ✅ Selected only if long press happened
                            toggleSelection: { viewModel.toggleSelection(for: medicine) }
                        )
                        .background(viewModel.isSelecting && viewModel.selectedMedicines.contains(medicine) ? Color.gray.opacity(0.3) : Color.clear)
                        .contentShape(Rectangle())
                        // Il tap ha priorità, anche se è presente il long press
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                if viewModel.isSelecting {
                                    viewModel.toggleSelection(for: medicine)
                                } else {
                                    selectedMedicine = medicine
                                }
                            }
                        )
                        .gesture(
                            LongPressGesture().onEnded { _ in
                                withAnimation {
                                    viewModel.enterSelectionMode(with: medicine) 
                                }
                            }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { newValue in
                if !newValue { selectedMedicine = nil }
            }
        )) {
            if let medicine = selectedMedicine {
                MedicineDetailView(
                    medicine: medicine,
                    package: getPackage(for: medicine)
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: selectedMedicine) { newValue in
            if (newValue == nil) {
                viewModel.clearSelection() 
            }
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
