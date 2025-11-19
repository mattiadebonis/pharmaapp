//  ContentView.swift
//  PharmaApp – Liquid Glass layout 2025
//
//  Created by Mattia De Bonis on 09/12/24.
//  Redesigned on 16/07/25 to match new UX blueprint

import SwiftUI
import CoreData

struct ContentView: View {
    // MARK: – Dependencies
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appVM: AppViewModel
    @StateObject private var feedVM = FeedViewModel()

    private enum AppTab: Hashable {
        case oggi
        case medicine
        case nuovo
    }

    @State private var selectedTab: AppTab = .oggi
    @State private var previousTab: AppTab = .oggi
    @State private var isAddPresented = false
    @State private var isSettingsPresented = false

    // Init fake data once
    init() {
        DataManager.shared.initializePharmaciesDataIfNeeded()
        DataManager.shared.initializeOptionsIfEmpty()
    }

    // MARK: – UI
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                // TAB 1 – Insights (a sinistra)
                Tab("Insights", systemImage: "sparkles", value: AppTab.oggi) {
                    NavigationStack {
                        FeedView(viewModel: feedVM, mode: .insights)
                    }
                }

                // TAB 2 – Medicine (a sinistra)
                Tab("Medicine", systemImage: "pills", value: AppTab.medicine) {
                    NavigationStack {
                        FeedView(viewModel: feedVM, mode: .medicines)
                            .navigationTitle("Armadio dei farmaci")
                            .navigationBarTitleDisplayMode(.large)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button {
                                        isSettingsPresented = true
                                    } label: {
                                        Image(systemName: "gearshape")
                                    }
                                }
                            }
                    }
                }

                // TAB 3 – Nuovo (separato a destra grazie al role: .search)
                Tab("Nuovo",
                    systemImage: "plus.circle.fill",
                    value: AppTab.nuovo,
                    role: .search
                ) {
                    // Non mostriamo realmente un contenuto,
                    // perché usiamo il tab come "azione"
                    Color.clear
                }
            }
            .onChange(of: selectedTab) { newValue in
                if newValue == .nuovo {
                    // Mostra il foglio "Nuovo" e torna al tab precedente
                    isAddPresented = true
                    selectedTab = previousTab
                } else {
                    previousTab = newValue
                }
            }

            // Floating action bar solo in tab Medicine quando si seleziona
            if selectedTab == .medicine && feedVM.isSelecting {
                floatingActionBar()
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isAddPresented) {
            NavigationStack {
                NewMedicineView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { isAddPresented = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                OptionsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { isSettingsPresented = false }
                        }
                    }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: – Floating bar (selezione multipla)
    @ViewBuilder
    private func floatingActionBar() -> some View {
        HStack {
            if feedVM.allRequirePrescription {
                Button("Richiedi Ricetta") {
                    feedVM.requestPrescription()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Acquistato") {
                feedVM.markAsPurchased()
            }

            Button("Assunto") {
                feedVM.markAsTaken()
            }

            Spacer()

            Button("Annulla") {
                feedVM.cancelSelection()
            }
            .foregroundStyle(.red)
        }
        .font(.body)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 10)
    }

}

// MARK: – Preview
#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
