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
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    sheetHero
                    formCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 180)
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                if nome.isEmpty { nome = appViewModel.query }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            captureActionsPanel
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $isShowingCamera, onDismiss: processCapturedImage) {
            ImagePickerView(sourceType: .camera) { image in
                capturedImage = image
            }
        }
        .onDisappear { speech.stop() }
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

    private var sheetHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "pills.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.white.opacity(0.7))
                .font(.system(size: 52))
                .padding()
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            Text("Nuovo farmaco")
                .font(.title2.weight(.bold))
            Text("Aggiungi un medicinale al tuo armadietto")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(LinearGradient(colors: [.teal.opacity(0.4), .blue.opacity(0.2)], startPoint: .leading, endPoint: .trailing), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 14, x: 0, y: 8)
        )
    }
    
    private var formCard: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nome del farmaco")
                    .font(.subheadline.weight(.semibold))
                TextField("", text: $nome, prompt: Text("Es. Brintellix 10 mg"))
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                Text("Inserisci il nome come scritto sulla scatola")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Unità per confezione")
                    .font(.subheadline.weight(.semibold))
                TextField("", text: $numeroStr, prompt: Text("Es. 28 compresse"))
                    .keyboardType(.numberPad)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
            }
            
            Toggle(isOn: $obbligoRicetta) {
                Text("Richiede ricetta medica")
                    .font(.subheadline)
            }
            .toggleStyle(SwitchToggleStyle(tint: .teal))
            
            Button {
                createMedicine()
            } label: {
                Label("Aggiungi all'armadietto", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .disabled(!canCreate)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(LinearGradient(colors: [.teal.opacity(0.35), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
        )
    }
    
    @ViewBuilder
    private var captureActionsPanel: some View {
        VStack(spacing: 12) {
            Text("Puoi anche scansionare la scatola o dettare il farmaco")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                captureButton(icon: "vial.viewfinder", title: "Scansiona scatola") {
                    isShowingCamera = true
                }
                if speech.isRecording {
                    recordingIndicator
                } else {
                    captureButton(icon: "mic.fill", title: "Detta il farmaco") {
                        startVoiceInput()
                    }
                }
            }
            Text("Puoi modificare queste info in qualsiasi momento.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
    }
    
    @ViewBuilder
    private func captureButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(
                        Circle()
                            .fill(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    private var recordingIndicator: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.4), lineWidth: 6)
                    .frame(width: 62, height: 62)
                    .scaleEffect(isPulsing ? 1.15 : 0.9)
                    .opacity(isPulsing ? 0.2 : 0.5)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
                Circle()
                    .fill(Color.red)
                    .frame(width: 54, height: 54)
                Image(systemName: "mic.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 22, weight: .bold))
            }
            Text("Sto ascoltando…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear { isPulsing = true }
        .onDisappear { isPulsing = false }
        .accessibilityLabel("Registrazione in corso")
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
