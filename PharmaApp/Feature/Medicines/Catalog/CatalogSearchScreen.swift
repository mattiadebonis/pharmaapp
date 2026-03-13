import SwiftUI
import UIKit
import Vision

struct CatalogSearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore

    let autoStartScan: Bool
    let onSelect: (CatalogSelection) -> Void

    @State private var searchText = ""
    @State private var shouldAutoFocusSearch = false
    @State private var didHandleInitialAppearance = false
    @State private var catalogSelections: [CatalogSelection] = []
    @State private var catalogCountry: CatalogCountry = .fallback()
    @State private var isLoading = false
    @State private var isScanPresented = false
    @State private var isProcessingScan = false
    @State private var catalogErrorMessage: String?
    @State private var scanErrorMessage: String?
    @State private var showScanError = false

    private let repository = CatalogSelectionRepository()

    init(
        autoStartScan: Bool = false,
        onSelect: @escaping (CatalogSelection) -> Void
    ) {
        self.autoStartScan = autoStartScan
        self.onSelect = onSelect
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredResults: [CatalogSelection] {
        repository.searchSelections(
            query: trimmedSearchText,
            in: catalogSelections,
            excludingIdentityKeys: []
        )
    }

    private var catalogSearchToken: String {
        "\(catalogCountry.rawValue)|\(trimmedSearchText)"
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Caricamento catalogo...")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            } else if trimmedSearchText.isEmpty {
                Section {
                    Button {
                        startScan()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cerca nel catalogo")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Digita il nome del farmaco oppure usa lo scanner.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            } else if filteredResults.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(catalogErrorMessage == nil ? "Nessun risultato" : "Catalogo non disponibile")
                            .font(.headline)
                        Text(
                            catalogErrorMessage
                            ?? "Nessuna corrispondenza per \"\(trimmedSearchText)\"."
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Section(header: Text("Risultati \(filteredResults.count)")) {
                    ForEach(filteredResults) { selection in
                        Button {
                            onSelect(selection)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(repository.titleCase(selection.name))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(repository.naturalPackageLabel(for: selection))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Cerca il farmaco"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("Catalogo")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") {
                    dismiss()
                }
            }
        }
        .task {
            await loadCatalogPreferencesIfNeeded()
        }
        .task(id: catalogSearchToken) {
            await refreshCatalogResults()
        }
        .onAppear {
            guard !didHandleInitialAppearance else { return }
            didHandleInitialAppearance = true
            if autoStartScan {
                startScan()
            } else {
                shouldAutoFocusSearch = true
            }
        }
        .background(
            SearchFieldAutoFocusInstaller(shouldFocus: shouldAutoFocusSearch) {
                shouldAutoFocusSearch = false
            }
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
            Text(scanErrorMessage ?? "Riprova con una foto più nitida.")
        }
    }

    @MainActor
    private func loadCatalogPreferencesIfNeeded() async {
        guard let option = try? appDataStore.provider.medicines.fetchCurrentOption() else {
            return
        }
        catalogCountry = option.resolvedCatalogCountry
    }

    @MainActor
    private func refreshCatalogResults() async {
        let query = trimmedSearchText
        guard !query.isEmpty else {
            catalogSelections = []
            isLoading = false
            catalogErrorMessage = nil
            return
        }

        isLoading = true
        catalogErrorMessage = nil

        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            catalogSelections = try await appDataStore.provider.catalog.searchCatalog(
                country: catalogCountry,
                query: query,
                limit: 40
            )
            isLoading = false
        } catch is CancellationError {
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            catalogSelections = []
            isLoading = false
            catalogErrorMessage = error.localizedDescription
        }
    }

    private func startScan() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            scanErrorMessage = "La fotocamera non è disponibile su questo dispositivo."
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

            Task { @MainActor in
                await handleRecognizedCatalogText(text)
            }
        }
    }

    @MainActor
    private func handleRecognizedCatalogText(_ text: String) async {
        do {
            let selections = try await appDataStore.provider.catalog.searchCatalog(
                country: catalogCountry,
                query: text,
                limit: 60
            )
            catalogSelections = selections
            isProcessingScan = false

            if let match = repository.matchSelection(
                fromRecognizedText: text,
                candidates: selections
            ) {
                searchText = match.name
                return
            }

            if !selections.isEmpty {
                searchText = text
                return
            }

            scanErrorMessage = "Nessuna corrispondenza trovata nel catalogo."
            showScanError = true
        } catch {
            isProcessingScan = false
            scanErrorMessage = error.localizedDescription
            showScanError = true
        }
    }

    private func recognizeText(in image: UIImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage
                ?? image.ciImage.flatMap({ CIContext().createCGImage($0, from: $0.extent) }) else {
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
}
