//
//  ContentView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

import SwiftUI
import CoreData
import Vision

struct ContentView: View {

    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject var appViewModel: AppViewModel

    @FetchRequest(fetchRequest: Pharmacie.extractPharmacies(), animation: .default) var pharmacies: FetchedResults<Pharmacie>

    // Colorazioni personalizzate
    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    let pastelGreen = Color(red: 179/255, green: 207/255, blue: 190/255, opacity: 1.0)
    let textColor = Color(red: 47/255, green: 47/255, blue: 47/255, opacity: 1.0)
    let pastelPink = Color(red: 248/255, green: 200/255, blue: 220/255, opacity: 1.0)
    
    @State private var isSearchIndexPresented = false
    @State private var isSettingsPresented = false
    @State private var isShowingCamera = false
    @State private var capturedImage: UIImage? = nil

    init() {
        DataManager.shared.initializeMedicinesDataIfNeeded()
        DataManager.shared.initializePharmaciesDataIfNeeded()
        DataManager.shared.initializeOptionsIfEmpty()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // Barra impostazioni in alto a destra
                HStack {
                    Spacer()
                    Button(action: { isSettingsPresented = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(pastelBlue)
                            .padding()
                    }
                }
                .padding()
                
                if appViewModel.suggestNearestPharmacies {
                    Button(action: {
                        appViewModel.isStocksIndexPresented = true
                    }) {
                        Image(systemName: "cross")
                        Text("Rifornisci i farmaci in esaurimento")
                        Spacer()
                    }
                    .bold()
                    .foregroundColor(.white)
                    .padding(20)
                    .background(Color.blue)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 220/255, green: 220/255, blue: 220/255), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
                
                // TextField personalizzato con bottone fotocamera
                HStack {
                    TextField("Cerca", text: $appViewModel.query)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    Button(action: {
                        isShowingCamera = true
                    }) {
                        Image(systemName: "camera.fill")
                            .foregroundColor(pastelBlue)
                            .padding(10)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 5)
                
                // Mostra la Feed o l'indice di ricerca in base al contenuto della query
                if appViewModel.query.isEmpty {
                    FeedView()
                } else {
                    SearchIndex()
                }
            }
            .padding()
        }
        .sheet(isPresented: $isSettingsPresented) {
            OptionsView()
                .environment(\.managedObjectContext, managedObjectContext)
        }
        .sheet(isPresented: $appViewModel.isStocksIndexPresented) {
            PharmaciesIndex()
        }
        // Apertura della fotocamera con sheet
        .sheet(isPresented: $isShowingCamera, onDismiss: processCapturedImage) {
            ImagePicker(sourceType: .camera, selectedImage: $capturedImage)
        }
    }
    
    func processCapturedImage() {
        if let image = capturedImage {
            extractText(from: image)
        }
    }
    
    func extractText(from image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { (request, error) in
            guard error == nil else {
                print("Errore OCR: \(error!.localizedDescription)")
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            let fullText = recognizedStrings.joined(separator: " ")
            DispatchQueue.main.async {
                appViewModel.query = fullText
            }
        }
        request.recognitionLevel = .accurate
        
        do {
            try requestHandler.perform([request])
        } catch {
            print("Errore durante l'esecuzione dell'OCR: \(error.localizedDescription)")
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .camera
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
         let picker = UIImagePickerController()
         picker.sourceType = sourceType
         picker.delegate = context.coordinator
         return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
         let parent: ImagePicker
         init(_ parent: ImagePicker) {
             self.parent = parent
         }
         func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
             if let image = info[.originalImage] as? UIImage {
                  parent.selectedImage = image
             }
             parent.presentationMode.wrappedValue.dismiss()
         }
         func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
             parent.presentationMode.wrappedValue.dismiss()
         }
    }
}

#Preview {
    ContentView()
}