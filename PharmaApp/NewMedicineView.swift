import SwiftUI
import CoreData

struct NewMedicineView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    // Medicine fields (semplificati)
    @State private var nome: String = ""
    @State private var obbligoRicetta: Bool = false

    // Unico campo confezione richiesto: numero unità per confezione
    @State private var numeroStr: String = ""

    // After creation open details
    @State private var showDetail: Bool = false
    @State private var createdMedicine: Medicine?
    @State private var createdPackage: Package?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Nuovo medicinale")) {
                    TextField("Nome", text: $nome)
                    Toggle("Obbligo ricetta", isOn: $obbligoRicetta)
                }

                Section(header: Text("Confezione")) {
                    TextField("Unità per confezione", text: $numeroStr)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Nuovo medicinale")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") { createMedicine() }
                        .disabled(!canCreate)
                }
            }
            .onAppear {
                if nome.isEmpty { nome = appViewModel.query }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showDetail) {
            if let m = createdMedicine, let p = createdPackage {
                MedicineDetailView(medicine: m, package: p)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var canCreate: Bool {
        guard !nome.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let numero = Int32(numeroStr), numero > 0 else { return false }
        return true
    }

    private func createMedicine() {
        let medicine = Medicine(context: context)
        medicine.id = UUID()
        medicine.nome = nome.trimmingCharacters(in: .whitespaces)
        // Campi rimossi: salviamo valori neutri
        medicine.principio_attivo = ""
        medicine.obbligo_ricetta = obbligoRicetta

        let package = Package(context: context)
        package.id = UUID()
        // Campi rimossi: valori di default/"vuoti"
        package.tipologia = ""
        package.unita = ""
        package.volume = ""
        package.valore = 0
        package.numero = Int32(numeroStr) ?? 0
        package.medicine = medicine
        medicine.addToPackages(package)

        do {
            try context.save()
            createdMedicine = medicine
            createdPackage = package
            showDetail = true
        } catch {
            print("Errore salvataggio medicinale: \(error)")
        }
    }
}
