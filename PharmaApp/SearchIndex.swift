//
//  SearchIndex.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 16/12/24.
//

import SwiftUI
import CoreData

struct SearchIndex: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var appViewModel: AppViewModel

    // Stato form inserimento manuale (semplificato)
    @State private var nome: String = ""
    @State private var obbligoRicetta: Bool = false
    @State private var numeroStr: String = ""

    // Presentazione dettaglio dopo creazione
    @State private var isMedicineSheetPresented: Bool = false
    @State private var createdMedicine: Medicine?
    @State private var createdPackage: Package?
    @State private var createdEntry: MedicinePackage?

    var body: some View {
        Form {
            Section(header: Text("Nuovo medicinale")) {
                TextField("Nome", text: $nome)
                    .onAppear { if nome.isEmpty { nome = appViewModel.query } }
                Toggle("Obbligo ricetta", isOn: $obbligoRicetta)
            }

            Section(header: Text("Confezione")) {
                TextField("Unità per confezione", text: $numeroStr)
                    .keyboardType(.numberPad)
            }

            Section {
                Button(action: createMedicine) {
                    Label("Crea e apri dettagli", systemImage: "plus.circle.fill")
                }
                .disabled(!canCreate)
            }
        }
        .onAppear {
            // Precompila il nome con la query, se presente
            if nome.isEmpty { nome = appViewModel.query }
        }
        .sheet(isPresented: $isMedicineSheetPresented) {
            if let m = createdMedicine, let p = createdPackage {
                MedicineDetailView(medicine: m, package: p, medicinePackage: createdEntry)
                    .presentationDetents([.medium, .large])
            } else {
                Text("Errore creazione medicinale")
            }
        }
    }

    private var canCreate: Bool {
        // Nome e numero unità per confezione obbligatori (> 0)
        guard !nome.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let numero = Int32(numeroStr), numero > 0 else { return false }
        return true
    }

    private func createMedicine() {
        let medicine = Medicine(context: context)
        medicine.id = UUID()
        medicine.nome = nome.trimmingCharacters(in: .whitespaces)
        medicine.principio_attivo = ""
        medicine.obbligo_ricetta = obbligoRicetta

        let package = Package(context: context)
        package.id = UUID()
        package.tipologia = ""
        package.unita = ""
        package.volume = ""
        package.valore = 0
        package.numero = Int32(numeroStr) ?? 0
        package.medicine = medicine
        medicine.addToPackages(package)
        let entry = MedicinePackage(context: context)
        entry.id = UUID()
        entry.created_at = Date()
        entry.medicine = medicine
        entry.package = package
        entry.cabinet = nil
        medicine.addToMedicinePackages(entry)

        do {
            try context.save()
            createdMedicine = medicine
            createdPackage = package
            createdEntry = entry
            isMedicineSheetPresented = true
        } catch {
            // In un'app reale: mostra un alert. Qui fallback silenzioso.
            print("Errore salvataggio medicinale: \(error)")
        }
    }
}

struct SearchIndex_Previews: PreviewProvider {
    static var previews: some View {
        SearchIndex()
            .environmentObject(AppViewModel())
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
