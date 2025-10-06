//  ContentView.swift
//  PharmaApp – Liquid Glass layout 2025
//
//  Created by Mattia De Bonis on 09/12/24.
//  Redesigned on 16/07/25 to match new UX blueprint
//
//  NOTE: alcuni tipi (FeedViewModel, FeedView, SearchIndex, etc.)
//  sono riutilizzati dal tuo progetto. Questa bozza si focalizza
//  esclusivamente sull’impostazione visuale; collega i view model
//  dove necessario.

import SwiftUI
import CoreData
import Vision

struct ContentView: View {
    // MARK: – Dependencies
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appVM: AppViewModel
    @StateObject private var feedVM = FeedViewModel()

    @State private var isSettingsPresented = false
    @State private var isNewMedicinePresented = false
    @State private var isShowingCamera  = false
    @State private var capturedImage: UIImage?

    // Init fake data once
    init() {
        // Medicines are now entered manually by users; no JSON preload
        DataManager.shared.initializePharmaciesDataIfNeeded()
        DataManager.shared.initializeOptionsIfEmpty()
    }

    // MARK: – UI
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            smartBanner
                            searchField
                            // OPTIONAL segmented picker → comment if not used
//                            filterSegment
                            contentList
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
                // Restore bulk action bar from original implementation
                if feedVM.isSelecting { floatingActionBar() }
                
                // Floating Add button (visible when not selecting)
                if !feedVM.isSelecting {
                    VStack { 
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { isNewMedicinePresented = true }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(Color.accentColor))
                                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                            }
                            .accessibilityLabel("Aggiungi medicinale")
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Le mie medicine")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addMedicine) {
                        Image(systemName: "gearshape")
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.accentColor.opacity(0.1)))
                    }
                    .accessibilityLabel("Impostazioni")
                }
            }
            .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            LinearGradient(colors: [Color.white.opacity(0.25), Color.blue.opacity(0.060)],
                                        startPoint: .bottomLeading,
                                        endPoint: .topTrailing)
                        )
                        .ignoresSafeArea()
                )
        }
        .sheet(isPresented: $isSettingsPresented) { OptionsView() }
        .sheet(isPresented: $isNewMedicinePresented) { NewMedicineView() }
        // ↓ evita che la floating bar venga coperta dalla tastiera
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    @ViewBuilder
    private func floatingActionBar() -> some View {
        VStack {
            Spacer()
            HStack {
                if feedVM.allRequirePrescription {
                    Button("Richiedi Ricetta") { feedVM.requestPrescription() }
                }
                Button("Acquistato") { feedVM.markAsPurchased() }
                Button("Assunto") { feedVM.markAsTaken() }
                Spacer()
                Button("Annulla") { feedVM.cancelSelection() }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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

    // MARK: – Sub‑views
    /// Banner rifornimento (appare solo quando necessario)
    private var smartBanner: some View {
        Group {
            if appVM.suggestNearestPharmacies {
                Button {
                    appVM.isStocksIndexPresented = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Rifornisci i farmaci in esaurimento")
                            .font(.body.bold())
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// Campo di ricerca con icona fotocamera embedded
    private var searchField: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Cerca", text: $appVM.query)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
                .font(.body)
            Spacer()
            Button { isShowingCamera = true } label: {
                Image(systemName: "camera.fill")
                    .font(.body)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Apri fotocamera")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.white)))
        .padding(.horizontal, 24)

    }

    /// Segment "Oggi / Tutti" (commentato se non serve)
    

    /// Lista card o indice ricerca
    private var contentList: some View {
        Group {
            if appVM.query.isEmpty {
                FeedView(viewModel: feedVM)
            } else {
                SearchIndex()
            }
        }
    }

    // MARK: Floating bar (selezione multipla)
//    private var floatingActionBar: some View {
//        VStack(spacing: 0) {
//            Divider().opacity(0)
//            HStack {
//                if feedVM.allRequirePrescription {
//                    Button("Richiedi Ricetta") { feedVM.requestPrescription() }
//                }
//                Button("Acquistato") { feedVM.markAsPurchased() }
//                Button("Assunto") { feedVM.markAsTaken() }
//                Spacer()
//                Button("Annulla") { feedVM.cancelSelection() }
//            }
//            .font(.body)
//            .padding()
//            .frame(maxWidth: .infinity)
//            .background(.thinMaterial)
//            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
//            .shadow(radius: 10)
//            .padding(.horizontal, 16)
//            .padding(.bottom, 12)
//        }
//        .transition(.move(edge: .bottom))
//        .animation(.easeInOut, value: feedVM.isSelecting)
//    }

    // MARK: – Helpers
    private func addMedicine() {
        isSettingsPresented = true
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
            DispatchQueue.main.async { appVM.query = text }
        }
        request.recognitionLevel = .accurate
        try? handler.perform([request])
    }
}

// MARK: – Preview
#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
