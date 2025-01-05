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

    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    let pastelGreen = Color(red: 179/255, green: 207/255, blue: 190/255, opacity: 1.0)
    let textColor = Color(red: 47/255, green: 47/255, blue: 47/255, opacity: 1.0)
    let pastelPink = Color(red: 248/255, green: 200/255, blue: 220/255, opacity: 1.0)

    var filteredMedicines: [Medicine] {
        guard !searchItem.isEmpty else { return Array(medicines) }
        return medicines.filter { medicine in
            medicine.nome.lowercased().contains(searchItem.lowercased())
        }
    }

    @State private var searchItem = ""
    @State private var isShowElementPresented = false
    @State private var isMedicineSelected: Bool = false
    @State private var selectedMedicine: Medicine = Medicine()

    var body: some View {
        NavigationView {
            ScrollView {
                TextField("Cerca", text: $searchItem)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                    

                ForEach(filteredMedicines, id: \.self) { medicine in
                    Button(action: {
                        self.selectedMedicine = medicine
                        self.isMedicineSelected = true
                    }) {
                        HStack {
                            Image(systemName: "pill")
                                .foregroundColor(isMedicineSelected ? pastelBlue : textColor)
                            Text(medicine.nome)
                                .font(.headline)
                                .foregroundColor(isMedicineSelected ? pastelBlue : textColor)
                            Spacer()
                        }
                        .padding()
                    }
                    .background(NavigationLink("", destination: MedicineFormView(medicine: selectedMedicine, context: managedObjectContext), isActive: $isMedicineSelected))
                    Divider()
                }
            }
            .padding()
        }
    }
}



struct SearchIndex_Previews: PreviewProvider {
    static var previews: some View {
        SearchIndex()
    }
}
