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
// import Vision spostato nella schermata di creazione

struct ContentView: View {
    // MARK: – Dependencies
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appVM: AppViewModel
    @StateObject private var feedVM = FeedViewModel()

    @State private var isNewMedicinePresented = false
    @State private var selectedTab: Int = 0 // 0 = Medicine, 1 = Impostazioni

    // Init fake data once
    init() {
        // Medicines are now entered manually by users; no JSON preload
        DataManager.shared.initializePharmaciesDataIfNeeded()
        DataManager.shared.initializeOptionsIfEmpty()
    }

    // MARK: – UI
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                smartBanner
                                contentList
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                    }
                    if feedVM.isSelecting { floatingActionBar() }
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
                // Nessuna lente nella toolbar: la ricerca è una tab dedicata
            }
            .tabItem {
                Image(systemName: "pills")
                Text("Medicine")
            }
            .tag(0)

            NavigationStack {
                OptionsView()
            }
            .tabItem {
                Image(systemName: "gearshape")
                Text("Impostazioni")
            }
            .tag(1)
        }
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

    // Barra di ricerca rimossa come richiesto

    /// Segment "Oggi / Tutti" (commentato se non serve)
    

    /// Lista card o indice ricerca
    private var contentList: some View {
        // La tab Medicine mostra sempre il feed; la ricerca è in una tab separata
        FeedView(viewModel: feedVM)
    }

    // ...existing code...

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
    // addMedicine sheet removed; settings now in tab

    // Funzionalità fotocamera spostata nel form di creazione
}

// MARK: – Preview
#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
