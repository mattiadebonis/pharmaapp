//  ContentView.swift
//  PharmaApp – Liquid Glass layout 2025
//
//  Created by Mattia De Bonis on 09/12/24.
//  Redesigned on 16/07/25 to match new UX blueprint

import SwiftUI
import CoreData
import Foundation

struct ContentView: View {
    // MARK: – Dependencies
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appVM: AppViewModel
    @StateObject private var feedVM = FeedViewModel()

    private var todayCalendarSymbolName: String {
        let day = Calendar.current.component(.day, from: Date())
        return "\(day).calendar"
    }

    private enum AppTab: Hashable {
        case oggi
        case medicine
        case search
    }

    @State private var selectedTab: AppTab = .oggi
    @State private var isSettingsPresented = false
    @State private var showNewMedicineForm = false
    @State private var catalogSelection: CatalogSelection? = nil
    @State private var showCabinetSheet = false
    @State private var newCabinetName: String = ""

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
                Tab("Oggi", systemImage: todayCalendarSymbolName, value: AppTab.oggi) {
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

                // TAB 3 – Cerca (ruolo search, icona lente in posizione originale)
                Tab("Cerca",
                    systemImage: "magnifyingglass",
                    value: AppTab.search,
                    role: .search
                ) {
                    NavigationStack {
                        CatalogSearchScreen { selection in
                            catalogSelection = selection
                            showNewMedicineForm = true
                        }
                    }
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
        .sheet(isPresented: $showCabinetSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Nome cabinet")) {
                        TextField("Es. Antidolorifici", text: $newCabinetName)
                            .textInputAutocapitalization(.words)
                    }
                }
                .navigationTitle("Nuovo cabinet")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { showCabinetSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Crea") {
                            createCabinet()
                        }
                        .disabled(newCabinetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showNewMedicineForm) {
            NavigationStack {
                NewMedicineView(prefill: catalogSelection) {
                    showNewMedicineForm = false
                    selectedTab = .medicine
                }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { showNewMedicineForm = false }
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

    private func createCabinet() {
        let trimmed = newCabinetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ctx = PersistenceController.shared.container.viewContext
        let cabinet = Cabinet(context: ctx)
        cabinet.id = UUID()
        cabinet.name = trimmed
        do {
            try ctx.save()
            newCabinetName = ""
            showCabinetSheet = false
        } catch {
            print("Errore creazione cabinet: \(error)")
        }
    }

}

// MARK: – Preview
#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

// MARK: - Catalog selection models
struct CatalogSelection: Identifiable, Hashable {
    let id: String
    let name: String
    let principle: String
    let requiresPrescription: Bool
    let units: Int
    let tipologia: String
    let valore: Int32
    let unita: String
    let volume: String
    let packageLabel: String
}

// MARK: - Catalog search (Tab role .search)
struct CatalogSearchScreen: View {
    let onSelect: (CatalogSelection) -> Void
    
    var body: some View {
        CatalogSearchList(onSelect: onSelect)
            .navigationTitle("Cerca farmaco")
    }
}

private struct CatalogSearchList: View {
    let onSelect: (CatalogSelection) -> Void
    @State private var searchText: String = ""
    @State private var searchIsPresented: Bool = true
    @State private var catalog: [CatalogMedicine] = []
    @State private var selectedPackageId: String? = nil
    @FetchRequest(fetchRequest: Medicine.extractMedicines()) private var existingMedicines: FetchedResults<Medicine>
    
    var body: some View {
        List {
            if catalog.isEmpty {
                HStack {
                    ProgressView()
                    Text("Caricamento farmaci…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    loadCatalog()
                }
            } else if !filteredCatalog.isEmpty {
                ForEach(filteredCatalog) { med in
                    medicineRow(medicine: med)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .searchable(text: $searchText, isPresented: $searchIsPresented, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear {
            if catalog.isEmpty {
                loadCatalog()
            }
        }
    }
    
    private var filteredCatalog: [CatalogMedicine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return catalog.compactMap { med in
            let packageMatches = med.packages.filter { pkg in
                pkg.label.lowercased().contains(query) ||
                pkg.tipologia.lowercased().contains(query)
            }
            let medMatches = med.name.lowercased().contains(query) || med.principle.lowercased().contains(query)
            if medMatches {
                return med
            } else if !packageMatches.isEmpty {
                return CatalogMedicine(
                    id: med.id,
                    name: med.name,
                    principle: med.principle,
                    requiresPrescription: med.requiresPrescription,
                    dosageDescription: med.dosageDescription,
                    packages: packageMatches
                )
            }
            return nil
        }
    }
    
    // MARK: - Mapping helpers
    private func loadCatalog() {
        let raw = DataManager.shared.loadMedicinesFromJSON()
        catalog = raw.compactMap { mapCatalogMedicine(from: $0) }
    }
    
    private func mapCatalogMedicine(from data: [String: Any]) -> CatalogMedicine? {
        let id = data["id"] as? String ?? UUID().uuidString
        let medicinalInfo = data["medicinale"] as? [String: Any]
        let name = (medicinalInfo?["denominazioneMedicinale"] as? String)
            ?? (data["descrizioneFormaDosaggio"] as? String)
            ?? (data["principiAttiviIt"] as? [String])?.first
            ?? "Medicinale"
        
        let principiAttivi = data["principiAttiviIt"] as? [String] ?? []
        let descrizioniAtc = data["descrizioneAtc"] as? [String] ?? []
        let principle = {
            let joined = principiAttivi.joined(separator: ", ")
            if !joined.isEmpty { return joined }
            let fallback = descrizioniAtc.joined(separator: ", ")
            return fallback.isEmpty ? "" : fallback
        }()
        
        let confezioni = data["confezioni"] as? [[String: Any]] ?? []
        let requires = requiresPrescription(from: confezioni)
        let dosageDescription = data["descrizioneFormaDosaggio"] as? String ?? ""
        let packages: [CatalogPackage] = confezioni.compactMap { conf in
            let pkgId = conf["idPackage"] as? String ?? UUID().uuidString
            let label = conf["denominazionePackage"] as? String ?? "Confezione"
            let units = extractUnitCount(from: label)
            let volume = extractVolume(from: label)
            let dosage = parseDosage(from: dosageDescription.isEmpty ? label : dosageDescription)
            let pkgRequires = requiresPrescription(from: [conf])
            return CatalogPackage(
                id: pkgId,
                label: label,
                units: units,
                tipologia: label,
                dosageValue: dosage.value,
                dosageUnit: dosage.unit,
                volume: volume,
                requiresPrescription: pkgRequires
            )
        }
        
        return CatalogMedicine(
            id: id,
            name: name,
            principle: principle,
            requiresPrescription: requires,
            dosageDescription: dosageDescription,
            // Ogni farmaco ripetuto per ogni confezione: qui manteniamo una sola confezione
            // per record per avere una riga per confezione (allineato all'armadietto)
            packages: packages
        )
    }
    
    private func requiresPrescription(from packages: [[String: Any]]) -> Bool {
        for package in packages {
            if let intFlag = package["flagPrescrizione"] as? Int, intFlag != 0 { return true }
            if let boolFlag = package["flagPrescrizione"] as? Bool, boolFlag { return true }
            if let classe = (package["classeFornitura"] as? String)?.uppercased(),
               ["RR", "RRL", "OSP"].contains(classe) { return true }
            if let descrizioni = package["descrizioneRf"] as? [String],
               descrizioni.contains(where: { $0.lowercased().contains("prescrizione") }) { return true }
        }
        return false
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
    
    // MARK: - Row layout aligned a MedicineRowView style con chip confezioni
    private func medicineRow(medicine: CatalogMedicine) -> some View {
        let alreadyInCabinet = existingNames.contains(normalize(medicine.name))
        let display = matchedMedicine(for: medicine) ?? previewMedicine(for: medicine, packages: medicine.packages)
        return VStack(alignment: .leading, spacing: 8) {
            if let firstPkg = medicine.packages.first {
                MedicineRowView(medicine: display.medicine)
                    .environment(\.managedObjectContext, display.context)
            }
            
            // Info confezione già inclusa in MedicineRowView
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if alreadyInCabinet { return }
            if let firstPkg = medicine.packages.first {
                selectPackage(medicine: medicine, package: firstPkg)
            }
        }
    }

    private func selectPackage(medicine: CatalogMedicine, package: CatalogPackage) {
        if existingNames.contains(normalize(medicine.name)) { return }
        selectedPackageId = package.id
        searchText = ""
        searchIsPresented = false
        let selection = CatalogSelection(
            id: medicine.id,
            name: medicine.name,
            principle: medicine.principle,
            requiresPrescription: medicine.requiresPrescription || package.requiresPrescription,
            units: max(1, package.units),
            tipologia: package.tipologia,
            valore: package.dosageValue,
            unita: package.dosageUnit,
            volume: package.volume,
            packageLabel: package.label
        )
        onSelect(selection)
    }
    
    private func previewMedicine(for med: CatalogMedicine, packages: [CatalogPackage]) -> PreviewMedicine {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.parent = PersistenceController.shared.container.viewContext
        
        let medicine = Medicine(context: ctx)
        medicine.id = UUID()
        medicine.nome = med.name
        medicine.principio_attivo = med.principle
        medicine.obbligo_ricetta = med.requiresPrescription
        medicine.in_cabinet = false
        medicine.custom_stock_threshold = 0
        
        for pkg in packages {
            let package = Package(context: ctx)
            package.id = UUID()
            package.tipologia = pkg.tipologia
            package.numero = Int32(pkg.units)
            package.valore = pkg.dosageValue
            package.unita = pkg.dosageUnit
            package.volume = pkg.volume
            package.medicine = medicine
            medicine.addToPackages(package)
        }
        
        return PreviewMedicine(context: ctx, medicine: medicine)
    }
    
    private func matchedMedicine(for med: CatalogMedicine) -> PreviewMedicine? {
        if let existing = existingMedicines.first(where: { normalize($0.nome) == normalize(med.name) }) {
            return PreviewMedicine(context: PersistenceController.shared.container.viewContext, medicine: existing)
        }
        return nil
    }
    
    private struct PreviewMedicine {
        let context: NSManagedObjectContext
        let medicine: Medicine
    }
    
    private var existingNames: Set<String> {
        Set(existingMedicines.map { normalize($0.nome) })
    }
    
    private func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    // MARK: - Models
    private struct CatalogMedicine: Identifiable, Hashable {
        let id: String
        let name: String
        let principle: String
        let requiresPrescription: Bool
        let dosageDescription: String
        let packages: [CatalogPackage]
    }
    
    private struct CatalogPackage: Identifiable, Hashable {
        let id: String
        let label: String
        let units: Int
        let tipologia: String
        let dosageValue: Int32
        let dosageUnit: String
        let volume: String
        let requiresPrescription: Bool
    }
}
