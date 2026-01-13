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
import UIKit
// import Vision spostato nella schermata di creazione

struct ContentView: View {
    // MARK: – Dependencies
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appVM: AppViewModel
    @State private var isNewMedicinePresented = false
    @State private var showMedicineWizard: Bool = false
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
                    TodayView()
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
                    CabinetView()
                        .navigationTitle("Armadio dei farmaci")
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
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
                        showMedicineWizard = true
                    }
                }
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack { OptionsView() }
        }
        .sheet(isPresented: $showMedicineWizard) {
            MedicineWizardView(prefill: catalogSelection)
                .environmentObject(appVM)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .presentationDetents([.fraction(0.5), .large])
        }
    }

    private var todayCalendarSymbolName: String {
        if #available(iOS 17.0, *) {
            return "calendar.day.timeline.left"
        }
        return "calendar"
    }

    private var todayDayNumber: Int {
        Calendar.current.component(.day, from: Date())
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
    let day: Int

    var body: some View {
        let symbolName = "\(day).calendar"
        if let uiImage = UIImage(systemName: symbolName) {
            Image(uiImage: uiImage)
                .font(.system(size: 18, weight: .regular))
        } else {
            ZStack(alignment: .center) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .regular))
                Text("\(day)")
                    .font(.system(size: 11, weight: .semibold))
                    .offset(y: 2)
            }
        }
    }
}

// Placeholder ricerca catalogo se non è presente un componente dedicato.
struct CatalogSearchScreen: View {
    var onSelect: (CatalogSelection) -> Void
    @State private var searchText: String = ""
    @FocusState private var isSearching: Bool
    @State private var catalog: [CatalogSelection] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Caricamento catalogo…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if filteredResults.isEmpty {
                // Non mostrare farmaci se la ricerca è vuota
            } else {
                Section(header: Text("Risultati")) {
                    ForEach(filteredResults, id: \.id) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(camelCase(item.name))
                                    .font(.headline)
                                Text(naturalPackageLabel(for: item))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if !item.principle.isEmpty {
                                    Text(item.principle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca il farmaco")
        .onAppear { isSearching = true }
        .focused($isSearching)
        .task { loadCatalogIfNeeded() }
    }

    private var filteredResults: [CatalogSelection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return catalog
            .filter { item in
                item.name.localizedCaseInsensitiveContains(query)
                || item.principle.localizedCaseInsensitiveContains(query)
                || item.packageLabel.localizedCaseInsensitiveContains(query)
            }
            .prefix(40)
            .map { $0 }
    }

    private func loadCatalogIfNeeded() {
        guard catalog.isEmpty else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let items = loadCatalog()
            DispatchQueue.main.async {
                catalog = items
                isLoading = false
            }
        }
    }

    private func loadCatalog() -> [CatalogSelection] {
        guard let url = Bundle.main.url(forResource: "medicinali", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var results: [CatalogSelection] = []
        for entry in json.prefix(1200) { // evita liste troppo lunghe
            let medInfo = entry["medicinale"] as? [String: Any]
            let rawName = (medInfo?["denominazioneMedicinale"] as? String)
                ?? (entry["descrizioneFormaDosaggio"] as? String)
                ?? (entry["principiAttiviIt"] as? [String])?.first
                ?? ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let principles = entry["principiAttiviIt"] as? [String] ?? []
            let atc = entry["descrizioneAtc"] as? [String] ?? []
            let principle: String = {
                let joined = principles.joined(separator: ", ")
                if !joined.isEmpty { return joined }
                let fallback = atc.joined(separator: ", ")
                return fallback.isEmpty ? name : fallback
            }()

            let packages = entry["confezioni"] as? [[String: Any]] ?? []
            guard let firstPackage = packages.first else { continue }
            let pkgLabel = (firstPackage["denominazionePackage"] as? String ?? "Confezione").trimmingCharacters(in: .whitespacesAndNewlines)
            let dosage = parseDosage(from: entry["descrizioneFormaDosaggio"] as? String)
            let units = extractUnitCount(from: pkgLabel)
            let volume = extractVolume(from: pkgLabel)
            let requiresPrescription = prescriptionFlag(in: firstPackage)

            let selection = CatalogSelection(
                id: (firstPackage["idPackage"] as? String) ?? (entry["id"] as? String) ?? UUID().uuidString,
                name: name,
                principle: principle,
                requiresPrescription: requiresPrescription,
                packageLabel: pkgLabel,
                units: max(1, units),
                tipologia: pkgLabel,
                valore: dosage.value,
                unita: dosage.unit,
                volume: volume
            )
            results.append(selection)
        }
        return results.sorted { $0.name < $1.name }
    }

    private func naturalPackageLabel(for item: CatalogSelection) -> String {
        var parts: [String] = []
        if item.units > 0 {
            parts.append("\(item.units) unità")
        }
        if item.valore > 0 {
            let unit = item.unita.trimmingCharacters(in: .whitespacesAndNewlines)
            let dosage = unit.isEmpty ? "\(item.valore)" : "\(item.valore) \(unit)"
            parts.append(dosage)
        }
        if !item.volume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(item.volume)
        }
        if parts.isEmpty {
            let raw = item.packageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "Confezione" : camelCase(raw)
        }
        return parts.joined(separator: " • ")
    }

    private func parseDosage(from description: String?) -> (value: Int32, unit: String) {
        guard let text = description else { return (0, "") }
        let tokens = text.split(separator: " ")
        var value: Int32 = 0
        var unit = ""
        for (index, token) in tokens.enumerated() {
            let digitString = token.filter(\.isNumber)
            if let parsed = Int32(digitString), !digitString.isEmpty {
                value = parsed
                if index + 1 < tokens.count {
                    let possibleUnit = tokens[index + 1]
                    if possibleUnit.rangeOfCharacter(from: .letters) != nil || possibleUnit.contains("/") {
                        unit = String(possibleUnit)
                    }
                }
                break
            }
        }
        return (value, unit)
    }

    private func extractUnitCount(from text: String) -> Int {
        let pattern = "\\d+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last,
              let range = Range(last.range, in: text),
              let value = Int(text[range]) else {
            return 0
        }
        return value
    }

    private func extractVolume(from text: String) -> String {
        let uppercased = text.uppercased()
        let pattern = "\\d+\\s*(ML|L)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let range = NSRange(location: 0, length: (uppercased as NSString).length)
        if let match = regex.firstMatch(in: uppercased, range: range),
           let matchRange = Range(match.range, in: uppercased) {
            return uppercased[matchRange].lowercased()
        }
        return ""
    }

    private func prescriptionFlag(in package: [String: Any]) -> Bool {
        if let intFlag = package["flagPrescrizione"] as? Int, intFlag != 0 {
            return true
        }
        if let boolFlag = package["flagPrescrizione"] as? Bool, boolFlag {
            return true
        }
        if let classe = (package["classeFornitura"] as? String)?.uppercased(),
           ["RR", "RRL", "OSP"].contains(classe) {
            return true
        }
        if let descrizioni = package["descrizioneRf"] as? [String],
           descrizioni.contains(where: { $0.lowercased().contains("prescrizione") }) {
            return true
        }
        return false
    }

    private func camelCase(_ text: String) -> String {
        text
            .lowercased()
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}
