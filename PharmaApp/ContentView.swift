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
    @StateObject private var feedViewModel = FeedViewModel() 

    @FetchRequest(fetchRequest: Pharmacie.extractPharmacies(), animation: .default) var pharmacies: FetchedResults<Pharmacie>

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
        ZStack {
            VStack(alignment: .leading) {
                ScrollView {
                    VStack {
                        // Top settings button
                        HStack {
                            Spacer()
                            Button(action: { isSettingsPresented = true }) {
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(Color.blue)
                                    .padding()
                            }
                        }
                        .padding()

                        if appViewModel.suggestNearestPharmacies {
                            Button(action: {
                                appViewModel.isStocksIndexPresented = true
                            }) {
                                HStack {
                                    Image(systemName: "cross")
                                    Text("Rifornisci i farmaci in esaurimento")
                                    Spacer()
                                }
                            }
                            .bold()
                            .foregroundColor(.white)
                            .padding(20)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }

                        // Search bar with camera button
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
                                    .foregroundColor(Color.blue)
                                    .padding(10)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 5)

                        // Show FeedView or SearchIndex based on query
                        if appViewModel.query.isEmpty {
                            FeedView(viewModel: feedViewModel) // Pass ViewModel
                        } else {
                            SearchIndex()
                        }
                    }
                    
                }.padding()
                Spacer()
                if feedViewModel.isSelecting {
                    floatingActionBar()
                        .transition(.move(edge: .bottom))
                        .animation(.easeInOut, value: feedViewModel.isSelecting)
                        .zIndex(2) // Ensures it's above everything
                }
            }

            
        }
        .ignoresSafeArea(.keyboard, edges: .bottom) // Ensures it stays above the keyboard
        .sheet(isPresented: $isSettingsPresented) {
            OptionsView()
                .environment(\.managedObjectContext, managedObjectContext)
        }
        .sheet(isPresented: $appViewModel.isStocksIndexPresented) {
            PharmaciesIndex()
        }
        .sheet(isPresented: $isShowingCamera, onDismiss: processCapturedImage) {
            ImagePicker(sourceType: .camera, selectedImage: $capturedImage)
        }
    }

    @ViewBuilder
    private func floatingActionBar() -> some View {
        VStack {
            Spacer()
            HStack {
                if feedViewModel.allRequirePrescription {
                    Button("Richiedi Ricetta") {
                        feedViewModel.requestPrescription()
                    }
                }
                Button("Acquistato") {
                    feedViewModel.markAsPurchased()
                }
                Button("Assunto") {
                    feedViewModel.markAsTaken()
                }
                Spacer()
                Button("Annulla") {
                    feedViewModel.cancelSelection()
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(radius: 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(Color.white.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(white: 0.8), lineWidth: 1)
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
