import SwiftUI
import CoreData

struct NewMedicineView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    // Medicine fields
    @State private var nome: String = ""
    @State private var principioAttivo: String = ""
    @State private var obbligoRicetta: Bool = false

    // Package fields
    @State private var tipologia: String = ""
    @State private var valoreStr: String = ""
    @State private var unita: String = ""
    @State private var volume: String = ""
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
                    TextField("Principio attivo (opzionale)", text: $principioAttivo)
                    Toggle("Obbligo ricetta", isOn: $obbligoRicetta)
                }

                Section(header: Text("Confezione")) {
                    TextField("Tipologia (es. Compresse)", text: $tipologia)
                    TextField("Dosaggio (valore)", text: $valoreStr)
                        .keyboardType(.numberPad)
                    TextField("Unità (es. mg)", text: $unita)
                    TextField("Volume (es. 20 compresse)", text: $volume)
                    TextField("Numero confezione (opz.)", text: $numeroStr)
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
        guard !tipologia.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !unita.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard Int32(valoreStr) != nil else { return false }
        return true
    }

    private func createMedicine() {
        let medicine = Medicine(context: context)
        medicine.id = UUID()
        medicine.nome = nome.trimmingCharacters(in: .whitespaces)
        medicine.principio_attivo = principioAttivo
        medicine.obbligo_ricetta = obbligoRicetta

        let package = Package(context: context)
        package.id = UUID()
        package.tipologia = tipologia.trimmingCharacters(in: .whitespaces)
        package.unita = unita.trimmingCharacters(in: .whitespaces)
        package.volume = volume.trimmingCharacters(in: .whitespaces)
        package.valore = Int32(valoreStr) ?? 0
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

