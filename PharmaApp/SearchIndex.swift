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
                medicine.nome.lowercased().contains(appViewModel.query.lowercased()) ?? false
            }
        }
    }

    @State private var isShowElementPresented = false
    @State private var isMedicineSelected: Bool = false
    @State private var selectedMedicine: Medicine = Medicine()
    @State private var selectedPackage: Package = Package()
    var body: some View {
        NavigationView {
            ScrollView {
                ForEach(filteredMedicines, id: \.self) { medicine in
                    
                        ForEach(Array(medicine.packages ?? []), id: \.self) { package in
                            Button(action: {
                                self.selectedMedicine = medicine
                                self.isMedicineSelected = true
                                self.selectedPackage = package
                            }) {
                                HStack {
                                    Image(systemName: "pill")
                                        .foregroundColor(isMedicineSelected ? pastelBlue : textColor)
                                    Text("\(medicine.nome)")
                                        .foregroundColor(isMedicineSelected ? pastelBlue : textColor)

                                        .font(.headline)
                                    Text("\(package.tipologia) - \(package.valore) \(package.unita) - \(package.volume)")
                                        .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .foregroundColor(isMedicineSelected ? pastelBlue : textColor)
                                    Spacer()
                                }
                                .padding(.leading, 20)
                                .background(NavigationLink("", destination: MedicineFormView(medicine: selectedMedicine, package: selectedPackage, context: managedObjectContext), isActive: $isMedicineSelected))
                            }
                            Divider()

                        }
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
