//
//  MedicineRowView.swift
//  PharmaApp
//
//  Created by Mattia De Bonis on 28/12/24.
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
    var isSelected: Bool
    var toggleSelection: () -> Void

    private var currentOption: Option? {
        options.first
    }
    
    private var inEsaurimento: Bool {
        guard let option = currentOption else { return false }
        return medicine.isInEsaurimento(option: option, recurrenceManager: recurrenceManager)
    }
    
    private var totalPillsLeft: Int {
        guard let therapies = medicine.therapies else { return 0 }
        return Int(therapies.reduce(0) { partialResult, therapy in
            partialResult + therapy.leftover()
        })
    }
    
    @State private var showMedicineForm: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack{
                Text(medicine.nome)
                    .font(.title3)
                    .bold()
                    .foregroundColor(isSelected ? .gray : .primary)
                Spacer()

                HStack(spacing: 12){
                    if inEsaurimento {
                        HStack {
                            Text("X")
                            Text("Esaurimento")    
                            if medicine.obbligo_ricetta {
                                Text("(Obbligo di ricetta)")
                            }
                        }
                        .foregroundColor(.red)
                        .onAppear {
                            appViewModel.suggestNearestPharmacies = true
                        }
                    
                    } else {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark").foregroundColor(.green)
                        }.foregroundColor(.green)
                    }
                }
            }
            
            
            TherapyNextDoseView(medicine: medicine).padding(.top)

        }
        .padding(16)
        .background(isSelected ? Color.gray.opacity(0.3) : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray, lineWidth: 1)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection()
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
