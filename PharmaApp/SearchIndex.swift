//
//  SearchIndex.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 16/12/24.
//

import SwiftUI
import CoreData

struct SearchIndex: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Therapy.extractTherapies()) var therapies: FetchedResults<Therapy>
    @FetchRequest(fetchRequest: Medicine.extractMedicines()) var medicines: FetchedResults<Medicine>

    @EnvironmentObject var appViewModel: AppViewModel

    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    let pastelGreen = Color(red: 179/255, green: 207/255, blue: 190/255, opacity: 1.0)
    let textColor = Color(red: 47/255, green: 47/255, blue: 47/255, opacity: 1.0)
    let pastelPink = Color(red: 248/255, green: 200/255, blue: 220/255, opacity: 1.0)

    var filteredMedicines: [Medicine] {
        if appViewModel.query.isEmpty {
            return Array(medicines)
        } else {
            return medicines.filter { medicine in
                medicine.nome.lowercased().contains(appViewModel.query.lowercased())
            }
        }
    }

    // Variabili di stato per la gestione della sheet, ora opzionali
    @State private var isMedicineSheetPresented: Bool = false
    @State private var selectedMedicine: Medicine? = nil
    @State private var selectedPackage: Package? = nil
    
    var body: some View {
        VStack {
            ForEach(filteredMedicines, id: \.self) { medicine in
                ForEach(Array(medicine.packages ?? []), id: \.self) { package in
                    Button(action: {
                        // Assegniamo le istanze recuperate dal fetch, non creiamo oggetti "vuoti"
                        self.selectedMedicine = medicine
                        self.selectedPackage = package
                        self.isMedicineSheetPresented = true
                    }) {
                        HStack {
                            Image(systemName: "pill")
                                .foregroundColor(textColor)
                            Text("\(medicine.nome)")
                                .foregroundColor(textColor)
                                .font(.headline)
                            Text("\(package.tipologia) - \(package.valore) \(package.unita) - \(package.volume)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.leading, 20)
                    }
                    Divider()
                }
            }
        }
        .padding()
        // Presentazione della sheet con altezza a metà (detent medium)
        .sheet(isPresented: $isMedicineSheetPresented) {
            if let selectedMedicine = selectedMedicine, let selectedPackage = selectedPackage {
                MedicineDetailView(medicine: selectedMedicine, package: selectedPackage)
                    .presentationDetents([.medium])
            } else {
                // In caso di problema, mostriamo un messaggio di fallback
                Text("Seleziona un medicinale valido")
            }
        }
    }
}

struct SearchIndex_Previews: PreviewProvider {
    static var previews: some View {
        SearchIndex()
    }
}