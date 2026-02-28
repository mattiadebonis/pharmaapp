import SwiftUI
import CoreData
import Vision

struct CatalogAddMedicineView: View {
    private struct Feedback: Identifiable {
        enum Kind {
            case success
            case error

            var title: String {
                switch self {
                case .success:
                    return "Operazione completata"
                case .error:
                    return "Operazione non riuscita"
                }
            }
        }

        let id = UUID()
        let kind: Kind
        let message: String
    }

    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    private var medicines: FetchedResults<Medicine>

    let autoStartScan: Bool

    @State private var searchText: String = ""
    @State private var shouldAutoFocusSearch = false
    @State private var didHandleInitialAppearance = false
    @State private var catalogSelections: [CatalogSelection] = []
    @State private var isLoading = false
    @State private var isScanPresented = false
    @State private var isProcessingScan = false
    @State private var scanErrorMessage: String?
    @State private var showScanError = false
    @State private var feedback: Feedback?
    @State private var therapyContext: CatalogResolvedContext?

    private let repository = CatalogSelectionRepository()

    private var resolver: CatalogSelectionResolver {
        CatalogSelectionResolver(context: managedObjectContext, repository: repository)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var inCabinetIdentityKeys: Set<String> {
        repository.inCabinetIdentityKeys(from: Array(medicines))
    }

    private var filteredResults: [CatalogSelection] {
        repository.searchSelections(
            query: trimmedSearchText,
            in: catalogSelections,
            excludingIdentityKeys: inCabinetIdentityKeys
        )
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    loadingContent
                }
            } else if trimmedSearchText.isEmpty {
                Section {
                    introContent
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } else if filteredResults.isEmpty {
                Section {
                    emptyResultsContent
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } else {
                Section(header: Text("Risultati \(filteredResults.count)")) {
                    ForEach(filteredResults) { selection in
                        catalogRow(selection)
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
        .navigationTitle("Aggiungi farmaco")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") {
                    dismiss()
                }
            }
        }
        .task {
            loadCatalogIfNeeded()
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
        .sheet(item: $therapyContext) { context in
            NavigationStack {
                TherapyFormView(
                    medicine: context.medicine,
                    package: context.package,
                    context: managedObjectContext,
                    medicinePackage: context.entry,
                    onSave: {
                        therapyContext = nil
                        feedback = Feedback(
                            kind: .success,
                            message: "Terapia aggiunta e farmaco inserito nell'armadietto."
                        )
                    },
                    isEmbedded: true
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") {
                            therapyContext = nil
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
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
        .alert(item: $feedback) { feedback in
            Alert(
                title: Text(feedback.kind.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Caricamento catalogo")
                    .font(.subheadline.weight(.semibold))
                Text("Preparazione elenco farmaci...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var introContent: some View {
        Button {
            startScan()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "vial.viewfinder")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.tint)
                    .frame(width: 52, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Scannerizza la scatola del farmaco")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Tocca qui per usare lo scanner e riconoscere automaticamente il farmaco.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scannerizza la scatola del farmaco")
    }

    private var emptyResultsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nessun risultato", systemImage: "magnifyingglass")
                .font(.headline)
            Text("Nessuna corrispondenza fuori dall'armadietto per \"\(trimmedSearchText)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Prova con meno parole o usa lo scanner.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func catalogRow(_ selection: CatalogSelection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(repository.titleCase(selection.name))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(selection.requiresPrescription ? "Ricetta" : "Libera")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(selection.requiresPrescription ? Color.orange.opacity(0.18) : Color.green.opacity(0.18))
                    )
                    .foregroundStyle(selection.requiresPrescription ? .orange : .green)
            }

            Text(repository.naturalPackageLabel(for: selection))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    handleAddToCabinet(selection)
                } label: {
                    Text("Armadietto")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .blue, textColor: .white))

                Button {
                    handleAddTherapy(selection)
                } label: {
                    Text("Terapia")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .orange, textColor: .white))

                Button {
                    handleBuy(selection)
                } label: {
                    Text("Compra")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .green, textColor: .white))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func handleAddToCabinet(_ selection: CatalogSelection) {
        do {
            _ = try resolver.addToCabinet(selection)
            feedback = Feedback(kind: .success, message: "Aggiunto all'armadietto.")
        } catch {
            managedObjectContext.rollback()
            feedback = Feedback(
                kind: .error,
                message: "Non sono riuscito ad aggiungere il farmaco all'armadietto."
            )
        }
    }

    private func handleAddTherapy(_ selection: CatalogSelection) {
        do {
            let resolved = try resolver.prepareTherapy(selection)
            therapyContext = resolved
        } catch {
            managedObjectContext.rollback()
            feedback = Feedback(
                kind: .error,
                message: "Non sono riuscito ad aprire il form terapia."
            )
        }
    }

    private func handleBuy(_ selection: CatalogSelection) {
        do {
            _ = try resolver.buyOnePackage(selection)
            feedback = Feedback(
                kind: .success,
                message: "Confezione acquistata e scorte aggiornate."
            )
        } catch {
            managedObjectContext.rollback()
            feedback = Feedback(
                kind: .error,
                message: "Non sono riuscito a registrare l'acquisto."
            )
        }
    }

    private func loadCatalogIfNeeded() {
        guard catalogSelections.isEmpty else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let selections = repository.loadSelections()
            DispatchQueue.main.async {
                catalogSelections = selections
                isLoading = false
            }
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

            DispatchQueue.global(qos: .userInitiated).async {
                let match = repository.matchSelection(fromRecognizedText: text)
                DispatchQueue.main.async {
                    isProcessingScan = false
                    if let match {
                        searchText = match.name
                    } else {
                        scanErrorMessage = "Nessuna corrispondenza trovata nel catalogo."
                        showScanError = true
                    }
                }
            }
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
