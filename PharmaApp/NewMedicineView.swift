import SwiftUI
import CoreData
import Vision
import Speech
import AVFoundation
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

    // Voice input (placeholder for future implementation)
    @StateObject private var speech = SpeechRecognizer()
    @State private var showVoiceAlert = false
    @State private var micPermissionDenied = false
    @State private var isPulsing = false

    var body: some View {
        NavigationView {
            Form {
                // Campo nome senza icone aggiuntive
                TextField("Nome", text: $nome)

                // Campo confezione
                Section(header: Text("Confezione")) {
                    TextField("Unità per confezione", text: $numeroStr)
                        .keyboardType(.numberPad)
                }
            }
            .onAppear {
                if nome.isEmpty { nome = appViewModel.query }
            }
        }
        // Nasconde la navigation bar e il suo titolo
        .toolbar(.hidden, for: .navigationBar)
        // Pulsanti flottanti in basso a destra (microfono/+, e scan)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                // Pulsante Scan (fotocamera)
                Button {
                    isShowingCamera = true
                } label: {
                    Image(systemName: "vial.viewfinder")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Circle().fill(Color.accentColor))
                }
                .accessibilityLabel("Scansiona con fotocamera")

                // Se sta registrando: mostra indicatore recording animato al posto del bottone
                if speech.isRecording {
                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(0.6), lineWidth: 6)
                            .frame(width: 56, height: 56)
                            .scaleEffect(isPulsing ? 1.2 : 0.9)
                            .opacity(isPulsing ? 0.2 : 0.6)
                            .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.red))
                    }
                    .onAppear { isPulsing = true }
                    .onDisappear { isPulsing = false }
                    .accessibilityLabel("Registrazione in corso")
                } else {
                    // Pulsante principale: microfono (se nome vuoto) o + (se nome presente)
                    Button {
                        if nome.trimmingCharacters(in: .whitespaces).isEmpty {
                            startVoiceInput()
                        } else {
                            createMedicine()
                        }
                    } label: {
                        Image(systemName: nome.trimmingCharacters(in: .whitespaces).isEmpty ? "mic.fill" : "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .padding(16)
                            .background(Circle().fill(Color.accentColor))
                    }
                    .disabled(isPrimaryActionDisabled)
                    .opacity(isPrimaryActionDisabled ? 0.45 : 1.0)
                    .accessibilityLabel(nome.trimmingCharacters(in: .whitespaces).isEmpty ? "Detta nome medicinale" : "Crea medicinale")
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $isShowingCamera, onDismiss: processCapturedImage) {
            ImagePickerView(sourceType: .camera) { image in
                capturedImage = image
            }
        }
        .onDisappear { speech.stop() }
        // Alert solo per mancanza permessi
        .alert("Dettatura nome medicinale", isPresented: $showVoiceAlert) {
            Button("Apri Impostazioni") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Chiudi", role: .cancel) { }
        } message: {
            Text("Per usare la dettatura, consenti l'accesso al microfono e al riconoscimento vocale in Impostazioni.")
        }
        .sheet(isPresented: $showDetail, onDismiss: { dismiss() }) {
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

    private var isPrimaryActionDisabled: Bool {
        let isNameEmpty = nome.trimmingCharacters(in: .whitespaces).isEmpty
        return isNameEmpty ? false : !canCreate
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
            
            DispatchQueue.main.async {
                showDetail = true
            }
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

    private func startVoiceInput() {
        // Richiedi autorizzazioni e avvia la dettatura; autopopola dopo 2s di silenzio
        speech.onSilenceDetected = { text in
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty {
                // Sostituisci il campo Nome con l'ultima trascrizione stabile
                self.nome = spoken
            }
            // Default per abilitare il + se non specificato
            if self.numeroStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.numeroStr = "1"
            }
        }
        speech.requestAuthorization { granted in
            micPermissionDenied = !granted
            if granted {
                speech.start()
            } else {
                showVoiceAlert = true
            }
        }
    }
}
