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
    
    @ObservedObject var viewModel: FeedViewModel // Pass ViewModel from ContentView

    var body: some View {
        let medicineArray = Array(medicines)
        let sortedByWeight = medicineArray.sorted { $0.weight > $1.weight }

        VStack {
            ScrollView {
                VStack {
                    ForEach(sortedByWeight) { medicine in
                        MedicineRowView(
                            medicine: medicine,
                            isSelected: viewModel.selectedMedicines.contains(medicine),
                            toggleSelection: { viewModel.toggleSelection(for: medicine) }
                        )
                        .onLongPressGesture {
                            viewModel.enterSelectionMode(with: medicine)
                        }
                    }
                }
            }
        }
    }
}