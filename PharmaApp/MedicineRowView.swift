//
//  MedicineRowView.swift
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
    
    // Recuperiamo la prima Option disponibile
    private var currentOption: Option? {
        options.first
    }
    
    // Determiniamo se la medicina è in esaurimento (logica esistente)
    private var inEsaurimento: Bool {
        guard let option = currentOption else { return false }
        return medicine.isInEsaurimento(option: option, recurrenceManager: recurrenceManager)
    }
    
    // Calcoliamo il totale delle pillole rimanenti
    private var totalPillsLeft: Int {
        guard let therapies = medicine.therapies else { return 0 }
        return Int(therapies.reduce(0) { partialResult, therapy in
            partialResult + therapy.leftover()
        })
    }
    
    // Trova la prossima assunzione (dose) più vicina nel futuro tra tutte le terapie
    private var nextDoseDate: Date? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else {
            return nil
        }
        
        let now = Date()
        // Uniamo tutte le date di dose di tutte le terapie
        let futureDoseDates = therapies
            .compactMap({ $0.doses })               // estrae le doses (Set<Dose>?)
            .flatMap({ $0 })                         // “appiattisce” più set in un array
            .compactMap({ $0.time })                 // estrae le date (assumendo che time sia non opzionale oppure già sbloccato)
            .filter({ $0 > now })                    // consideriamo solo quelle future
        
        return futureDoseDates.min()  // la più vicina nel futuro
    }
    
    // Converte la prossima assunzione in una stringa breve (es. "08:00" se è oggi, altrimenti "15 feb")
    private var nextDoseString: String? {
        guard let nextDoseDate = nextDoseDate else { return nil }
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(nextDoseDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: nextDoseDate)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return formatter.string(from: nextDoseDate)
        }
    }
    
    @State private var showMedicineForm: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            
            Text(medicine.nome)
                .font(.title3)
                .bold()
            
            HStack(spacing: 12){
                if inEsaurimento {
                    HStack{
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
                        
                        Text("Al completo")
                    }.foregroundColor(.green)
                }

                if let nextDoseString = nextDoseString {
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                        Text(nextDoseString)
                    }.foregroundColor(.purple)
                }   
                Spacer()
            }.font(.system(size: 14))
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.86), lineWidth: 1)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
}