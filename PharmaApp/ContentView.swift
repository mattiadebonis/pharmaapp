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
    @State private var showNewMedicineForm: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var catalogSelection: CatalogSelection?

    enum AppTab: Hashable {
        case oggi
        case medicine
        case search
    }

    @State private var selectedTab: AppTab = .oggi

    // Init fake data once
    init() {
        // Medicines are now entered manually by users; no JSON preload
        DataManager.shared.initializePharmaciesDataIfNeeded()
        DataManager.shared.initializeOptionsIfEmpty()
    }

    // MARK: – UI
    var body: some View {
        TabView(selection: $selectedTab) {
            // TAB 1 – Insights
            Tab(value: AppTab.oggi) {
                NavigationStack {
                    FeedView(viewModel: feedVM, mode: .insights)
                }
            } label: {
                Label {
                    Text("Oggi")
                } icon: {
                    TodayCalendarIcon(day: todayDayNumber)
                }
            }

            // TAB 2 – Medicine
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

            // TAB 3 – Cerca (ruolo search)
            Tab("Cerca", systemImage: "plus", value: AppTab.search, role: .search) {
                NavigationStack {
                    CatalogSearchScreen { selection in
                        catalogSelection = selection
                        showNewMedicineForm = true
                    }
                }
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack { OptionsView() }
        }
        .sheet(isPresented: $showNewMedicineForm) {
            NewMedicineView(prefill: catalogSelection)
        }
    }

    private var todayCalendarSymbolName: String {
        if #available(iOS 17.0, *) {
            return "calendar.day.timeline.left"
        }
        return "calendar"
    }

    private var todayDayNumber: String {
        let day = Calendar.current.component(.day, from: Date())
        return "\(day)"
    }
}

// MARK: – Preview
#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

// Icona calendario con numero del giorno
struct TodayCalendarIcon: View {
    let day: String

    var body: some View {
        ZStack(alignment: .center) {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .regular))
            Text(day)
                .font(.system(size: 11, weight: .semibold))
                .offset(y: 2)
        }
    }
}

// Placeholder ricerca catalogo se non è presente un componente dedicato.
struct CatalogSearchScreen: View {
    var onSelect: (CatalogSelection) -> Void
    @State private var searchText: String = ""
    @FocusState private var isSearching: Bool

    var body: some View {
        List {
            Section {
                Button {
                    addMedicine(named: searchText)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(searchText.isEmpty ? "Aggiungi nuovo medicinale" : "Aggiungi \"\(searchText)\"")
                            .font(.headline)
                    }
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca o digita il farmaco")
        .onAppear { isSearching = true }
        .focused($isSearching)
    }

    private func addMedicine(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let selection = CatalogSelection(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "Nuovo farmaco" : trimmed,
            principle: "",
            requiresPrescription: false,
            packageLabel: "",
            units: 1,
            tipologia: "",
            valore: 0,
            unita: "",
            volume: ""
        )
        onSelect(selection)
    }
}
