import SwiftUI
import CoreData
import Vision
import UIKit

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
    
    // Camera/Text recognition
    @State private var isShowingCamera = false
    @State private var capturedImage: UIImage?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Nuovo medicinale")) {
                    HStack(spacing: 8) {
                        TextField("Nome", text: $nome)
                        Button {
                            isShowingCamera = true
                        } label: {
                            Image(systemName: "camera.fill")
                                .foregroundColor(.accentColor)
                        }
                        .accessibilityLabel("Scatta foto per riconoscere il nome")
                    }
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
        // Camera sheet
        .sheet(isPresented: $isShowingCamera, onDismiss: processCapturedImage) {
            ImagePickerView(sourceType: .camera) { image in
                capturedImage = image
            }
        }
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
    
    private func processCapturedImage() {
        guard let image = capturedImage else { return }
        extractText(from: image)
    }
    private func extractText(from image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request  = VNRecognizeTextRequest { req, err in
            guard err == nil, let obs = req.results as? [VNRecognizedTextObservation] else { return }
            let text = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            DispatchQueue.main.async {
                if self.nome.isEmpty { self.nome = text } else { self.nome += " " + text }
            }
        }
        request.recognitionLevel = .accurate
        try? handler.perform([request])
    }
}
