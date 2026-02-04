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
import Vision

struct ContentView: View {
    // MARK: – Dependencies
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appVM: AppViewModel
    @State private var isNewMedicinePresented = false
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
                }
            }

            // TAB 3 – Cerca (ruolo search)
            Tab("Cerca", systemImage: "plus", value: AppTab.search, role: .search) {
                NavigationStack {
                    CatalogSearchScreen { selection in
                        catalogSelection = selection
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { appVM.isSettingsPresented },
            set: { appVM.isSettingsPresented = $0 }
        )) {
            NavigationStack { OptionsView() }
        }
        .sheet(item: $catalogSelection) { selection in
            MedicineWizardView(prefill: selection) {
                selectedTab = .medicine
                catalogSelection = nil
            }
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
        .environmentObject(CodiceFiscaleStore())
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

// Placeholder ricerca catalogo se non è presente un componente dedicato.
struct CatalogSearchScreen: View {
    @EnvironmentObject private var appVM: AppViewModel
    var onSelect: (CatalogSelection) -> Void
    @State private var searchText: String = ""
    @FocusState private var isSearching: Bool
    @State private var catalog: [CatalogSelection] = []
    @State private var isLoading = false
    @State private var isScanPresented = false
    @State private var isProcessingScan = false
    @State private var scanErrorMessage: String?
    @State private var showScanError = false

    private struct CatalogEntry {
        let name: String
        let principle: String
        let packages: [CatalogPackage]
        let codes: [String]
    }

    private struct CatalogPackage {
        let id: String
        let label: String
        let units: Int
        let tipologia: String
        let dosageValue: Int32
        let dosageUnit: String
        let volume: String
        let requiresPrescription: Bool
        let codes: [String]
    }

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
        .navigationTitle("Cerca")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    appVM.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Impostazioni")
            }
        }
        .onAppear { isSearching = true }
        .focused($isSearching)
        .task { loadCatalogIfNeeded() }
        .background(
            SearchBarAccessoryInstaller(
                systemImage: "vial.viewfinder",
                accessibilityLabel: "Scansiona confezione",
                onTap: { startScan() }
            )
        )
        .fullScreenCover(isPresented: $isScanPresented) {
            ImagePicker(sourceType: .camera) { image in
                handleScanImage(image)
            }
            .ignoresSafeArea()
        }
        .overlay {
            if isProcessingScan {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Analisi in corso...")
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("Scansione non riuscita", isPresented: $showScanError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanErrorMessage ?? "Riprova con una foto piu nitida.")
        }
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

    private func startScan() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            scanErrorMessage = "La fotocamera non e disponibile su questo dispositivo."
            showScanError = true
            return
        }
        isScanPresented = true
    }

    private func handleScanImage(_ image: UIImage?) {
        isScanPresented = false
        guard let image else { return }
        isProcessingScan = true
        recognizeText(in: image) { text in
            guard let text, !text.isEmpty else {
                isProcessingScan = false
                scanErrorMessage = "Non sono riuscito a leggere testo dalla foto."
                showScanError = true
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let match = matchCatalog(from: text)
                DispatchQueue.main.async {
                    isProcessingScan = false
                    if let match {
                        onSelect(match)
                    } else {
                        scanErrorMessage = "Nessuna corrispondenza trovata nel catalogo."
                        showScanError = true
                    }
                }
            }
        }
    }

    private func recognizeText(in image: UIImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage ?? image.ciImage.flatMap({ CIContext().createCGImage($0, from: $0.extent) }) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if error != nil {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { completion(text.isEmpty ? nil : text) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["it-IT", "en-US"]

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func matchCatalog(from text: String) -> CatalogSelection? {
        let normalizedText = normalize(text)
        let textTokens = tokenSet(from: normalizedText)
        let textNumbers = numberTokens(from: normalizedText)
        let entries = loadCatalogEntries()

        var best: (selection: CatalogSelection, score: Double, singlePackage: Bool)?

        for entry in entries {
            let medScore = scoreMedicine(entry: entry, normalizedText: normalizedText, tokens: textTokens, numbers: textNumbers)
            if medScore < 4 { continue }

            for package in entry.packages {
                let pkgScore = scorePackage(package: package, normalizedText: normalizedText, tokens: textTokens, numbers: textNumbers)
                let total = medScore + pkgScore
                if best == nil || total > best!.score {
                    let selection = CatalogSelection(
                        id: package.id,
                        name: entry.name,
                        principle: entry.principle,
                        requiresPrescription: package.requiresPrescription,
                        packageLabel: package.label,
                        units: max(1, package.units),
                        tipologia: package.tipologia,
                        valore: package.dosageValue,
                        unita: package.dosageUnit,
                        volume: package.volume
                    )
                    best = (selection: selection, score: total, singlePackage: entry.packages.count == 1)
                }
            }
        }

        guard let best else { return nil }
        let threshold = best.singlePackage ? 6.0 : 8.0
        return best.score >= threshold ? best.selection : nil
    }

    private func loadCatalogEntries() -> [CatalogEntry] {
        guard let url = Bundle.main.url(forResource: "medicinale_example", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        let json = extractMedicineItems(from: data)
        guard !json.isEmpty else { return [] }

        var results: [CatalogEntry] = []
        for entry in json.prefix(1200) {
            let medInfo = entry["medicinale"] as? [String: Any]
            let rawName = (medInfo?["denominazioneMedicinale"] as? String)
                ?? (medicineValue("denominazioneMedicinale", in: entry) as? String)
                ?? (medicineValue("descrizioneFormaDosaggio", in: entry) as? String)
                ?? stringArray(from: medicineValue("principiAttiviIt", in: entry)).first
                ?? ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let principles = stringArray(from: medicineValue("principiAttiviIt", in: entry))
            let atc = stringArray(from: medicineValue("descrizioneAtc", in: entry))
            let principle: String = {
                let joined = principles.joined(separator: ", ")
                if !joined.isEmpty { return joined }
                let fallback = atc.joined(separator: ", ")
                return fallback.isEmpty ? name : fallback
            }()

            let medCodes: [String] = [
                medInfo?["codiceMedicinale"] as? String,
                (medInfo?["aic6"] as? Int).map(String.init)
            ].compactMap { $0 }

            let dosage = parseDosage(from: medicineValue("descrizioneFormaDosaggio", in: entry) as? String)
            let packages = (entry["confezioni"] as? [[String: Any]] ?? []).compactMap { pkg in
                let label = (packageValue("denominazionePackage", in: pkg) as? String ?? "Confezione").trimmingCharacters(in: .whitespacesAndNewlines)
                let units = extractUnitCount(from: label)
                let volume = extractVolume(from: label)
                let requiresPrescription = prescriptionFlag(in: pkg)
                let pkgId = (packageValue("idPackage", in: pkg) as? String) ?? UUID().uuidString
                let pkgCodes: [String] = [
                    packageValue("aic", in: pkg) as? String,
                    packageValue("idPackage", in: pkg) as? String
                ].compactMap { $0 }

                return CatalogPackage(
                    id: pkgId,
                    label: label,
                    units: max(1, units),
                    tipologia: label,
                    dosageValue: dosage.value,
                    dosageUnit: dosage.unit,
                    volume: volume,
                    requiresPrescription: requiresPrescription,
                    codes: pkgCodes
                )
            }

            if packages.isEmpty { continue }
            results.append(CatalogEntry(name: name, principle: principle, packages: packages, codes: medCodes))
        }
        return results
    }

    private func scoreMedicine(entry: CatalogEntry, normalizedText: String, tokens: Set<String>, numbers: Set<String>) -> Double {
        let nameNorm = normalize(entry.name)
        guard !nameNorm.isEmpty else { return 0 }
        let nameTokens = tokenSet(from: nameNorm)
        let overlap = nameTokens.intersection(tokens).count
        let ratio = Double(overlap) / Double(max(1, nameTokens.count))
        var score = Double(overlap) * 1.5 + ratio * 2.0
        if normalizedText.contains(nameNorm) {
            score += 6.0
        }
        for code in entry.codes where numbers.contains(code) {
            score += 4.0
        }
        return score
    }

    private func scorePackage(package: CatalogPackage, normalizedText: String, tokens: Set<String>, numbers: Set<String>) -> Double {
        let labelNorm = normalize(package.label)
        let labelTokens = tokenSet(from: labelNorm)
        let overlap = labelTokens.intersection(tokens).count
        let labelNumbers = numberTokens(from: labelNorm)
        let numberOverlap = labelNumbers.intersection(numbers).count
        var score = Double(overlap) * 1.0 + Double(numberOverlap) * 2.0
        if !labelNorm.isEmpty && normalizedText.contains(labelNorm) {
            score += 4.0
        }
        for code in package.codes where numbers.contains(code) {
            score += 5.0
        }
        return score
    }

    private func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
        let upper = folded.uppercased()
        let cleaned = upper.replacingOccurrences(of: "[^A-Z0-9]", with: " ", options: .regularExpression)
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSet(from normalized: String) -> Set<String> {
        let tokens = normalized.split(separator: " ")
        let filtered = tokens.map(String.init).filter { token in
            if token.allSatisfy(\.isNumber) { return true }
            return token.count > 1
        }
        return Set(filtered)
    }

    private func numberTokens(from normalized: String) -> Set<String> {
        let pattern = "\\d+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        var results = Set<String>()
        for match in matches {
            if let range = Range(match.range, in: normalized) {
                results.insert(String(normalized[range]))
            }
        }
        return results
    }

    private func loadCatalog() -> [CatalogSelection] {
        guard let url = Bundle.main.url(forResource: "medicinale_example", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        let json = extractMedicineItems(from: data)
        guard !json.isEmpty else { return [] }

        var results: [CatalogSelection] = []
        for entry in json.prefix(1200) { // evita liste troppo lunghe
            let medInfo = entry["medicinale"] as? [String: Any]
            let rawName = (medInfo?["denominazioneMedicinale"] as? String)
                ?? (medicineValue("denominazioneMedicinale", in: entry) as? String)
                ?? (medicineValue("descrizioneFormaDosaggio", in: entry) as? String)
                ?? stringArray(from: medicineValue("principiAttiviIt", in: entry)).first
                ?? ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let principles = stringArray(from: medicineValue("principiAttiviIt", in: entry))
            let atc = stringArray(from: medicineValue("descrizioneAtc", in: entry))
            let principle: String = {
                let joined = principles.joined(separator: ", ")
                if !joined.isEmpty { return joined }
                let fallback = atc.joined(separator: ", ")
                return fallback.isEmpty ? name : fallback
            }()

            let packages = entry["confezioni"] as? [[String: Any]] ?? []
            guard !packages.isEmpty else { continue }
            let dosage = parseDosage(from: medicineValue("descrizioneFormaDosaggio", in: entry) as? String)

            for package in packages {
                let pkgLabel = (packageValue("denominazionePackage", in: package) as? String ?? "Confezione")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let units = extractUnitCount(from: pkgLabel)
                let volume = extractVolume(from: pkgLabel)
                let requiresPrescription = prescriptionFlag(in: package)

                let selection = CatalogSelection(
                    id: (packageValue("idPackage", in: package) as? String) ?? (entry["id"] as? String) ?? UUID().uuidString,
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
        }
        return results.sorted {
            if $0.name == $1.name {
                return $0.packageLabel < $1.packageLabel
            }
            return $0.name < $1.name
        }
    }

    private func medicineValue(_ key: String, in entry: [String: Any]) -> Any? {
        let info = entry["informazioni"] as? [String: Any]
        let flags = entry["flags"] as? [String: Any]
        let principles = entry["principi"] as? [String: Any]
        let candidates: [[String: Any]?] = [entry, info, flags, principles]
        for candidate in candidates {
            if let value = candidate?[key], !(value is NSNull) {
                return value
            }
        }
        return nil
    }

    private func packageValue(_ key: String, in package: [String: Any]) -> Any? {
        let prescrizioni = package["prescrizioni"]
        var fallbacks: [[String: Any]?] = []
        if let dict = prescrizioni as? [String: Any] {
            fallbacks.append(dict)
        }
        fallbacks.append(package["informazioni"] as? [String: Any])

        var candidates: [[String: Any]?] = [package]
        candidates.append(contentsOf: fallbacks)

        for candidate in candidates {
            if let value = candidate?[key], !(value is NSNull) {
                return value
            }
        }

        if key == "flagPrescrizione" {
            if let bool = prescrizioni as? Bool { return bool }
            if let int = prescrizioni as? Int { return int }
            if let number = prescrizioni as? NSNumber { return number }
        }
        return nil
    }

    private func stringArray(from value: Any?) -> [String] {
        guard let value = value else { return [] }
        if let array = value as? [String] { return array }
        if let string = value as? String { return [string] }
        if let anyArray = value as? [Any] {
            return anyArray.compactMap { $0 as? String }
        }
        return []
    }

    private func boolValue(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let int = value as? Int32 { return int != 0 }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "si", "y", "t"].contains(normalized)
        }
        return false
    }

    private func extractMedicineItems(from data: Data) -> [[String: Any]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = json as? [[String: Any]] {
            return array
        }
        if let dict = json as? [String: Any] {
            return [dict]
        }
        return []
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
        let flagValue = packageValue("flagPrescrizione", in: package) ?? packageValue("prescrizione", in: package)
        if boolValue(flagValue) {
            return true
        }
        if let classe = (packageValue("classeFornitura", in: package) as? String)?.uppercased(),
           ["RR", "RRL", "OSP"].contains(classe) {
            return true
        }
        let descrizioni = stringArray(from: packageValue("descrizioneRf", in: package))
        if descrizioni.contains(where: requiresPrescriptionDescription) {
            return true
        }
        return false
    }

    private func requiresPrescriptionDescription(_ description: String) -> Bool {
        let lower = description.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("non soggetto") || lower.contains("senza ricetta") || lower.contains("senza prescrizione") || lower.contains("non richiede") {
            return false
        }
        return lower.contains("prescrizione") || lower.contains("ricetta")
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

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: (UIImage?) -> Void

        init(onImage: @escaping (UIImage?) -> Void) {
            self.onImage = onImage
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onImage(image)
        }
    }
}

private struct SearchBarAccessoryInstaller: UIViewControllerRepresentable {
    let systemImage: String
    let accessibilityLabel: String
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.installIfNeeded(from: uiViewController, systemImage: systemImage, label: accessibilityLabel)
    }

    final class Coordinator {
        var onTap: () -> Void
        private weak var installedField: UISearchTextField?
        private weak var installedButton: UIButton?

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        func installIfNeeded(from viewController: UIViewController, systemImage: String, label: String) {
            DispatchQueue.main.async {
                guard let searchController = viewController.findSearchController() else { return }
                let textField = searchController.searchBar.searchTextField
                if self.installedField === textField, let button = self.installedButton {
                    button.setImage(UIImage(systemName: systemImage), for: .normal)
                    button.accessibilityLabel = label
                    return
                }

                let button = UIButton(type: .system)
                button.setImage(UIImage(systemName: systemImage), for: .normal)
                button.tintColor = .label
                button.accessibilityLabel = label
                button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
                button.addAction(UIAction { [weak self] _ in
                    self?.onTap()
                }, for: .touchUpInside)

                textField.rightView = button
                textField.rightViewMode = .always
                textField.clearButtonMode = .whileEditing

                self.installedField = textField
                self.installedButton = button
            }
        }
    }
}

private extension UIViewController {
    func findSearchController() -> UISearchController? {
        var current: UIViewController? = self
        while let controller = current {
            if let searchController = controller.navigationItem.searchController {
                return searchController
            }
            current = controller.parent
        }

        if let nav = navigationController, let searchController = nav.topViewController?.navigationItem.searchController {
            return searchController
        }

        if let root = view.window?.rootViewController {
            return root.findSearchControllerInChildren()
        }

        return nil
    }

    func findSearchControllerInChildren() -> UISearchController? {
        if let searchController = navigationItem.searchController {
            return searchController
        }
        for child in children {
            if let searchController = child.findSearchControllerInChildren() {
                return searchController
            }
        }
        return nil
    }
}
