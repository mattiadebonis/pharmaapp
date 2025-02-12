//
//  TherapyRowView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 28/12/24.
//

import SwiftUI
import CoreData

struct MedicineRowView: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @EnvironmentObject var appViewModel: AppViewModel

    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    @StateObject private var medicineRowViewModel: MedicineRowViewModel = MedicineRowViewModel(managedObjectContext: PersistenceController.shared.container.viewContext)
    
    var medicine: Medicine
    
    private var currentOption: Option? {
        options.first
    }
    private var inEsaurimento: Bool {
        guard let option = currentOption else { return false }
        return medicine.isInEsaurimento(option: option, recurrenceManager: recurrenceManager)
    }

    private var packageForMedicineForm: Package? {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            return therapies.first?.package
        } else if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            let sortedLogs = purchaseLogs.sorted { $0.timestamp > $1.timestamp }
            return sortedLogs.first?.package
        }
        return nil
    }

    @State private var showMedicineForm: Bool = false

    var body: some View {

        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    
                    HStack {
                        Text(medicine.nome ?? "")
                            .font(.title3)
                            .bold()
    
                        if inEsaurimento {     
                            Image(systemName: "x.circle")
                                .foregroundColor(.red)
                                .onAppear {
                                    appViewModel.suggestNearestPharmacies = true
                                }

                        } else {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                        Spacer()
                    }
                }
                Spacer()
            }
        }
        .padding(20)
        .background(Color.white)
        .overlay(
             RoundedRectangle(cornerRadius: 8)
                 .stroke(Color(red: 220/255, green: 220/255, blue: 220/255), lineWidth: 1)
         )
        .cornerRadius(8)
        .contentShape(Rectangle()) 

        .sheet(isPresented: $showMedicineForm) {
            MedicineFormView(
                medicine: medicine, 
                package: packageForMedicineForm!
            )
        }
    }

    
}
