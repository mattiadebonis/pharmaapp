import SwiftUI

struct MedicineWizardView: View {
    enum QuickAction {
        case actions
        case addToCabinet
        case addPackage
        case addTherapy
    }

    private enum Screen {
        case actions
        case stock
    }

    @EnvironmentObject private var appDataStore: AppDataStore
    @Environment(\.dismiss) private var dismiss

    private let prefill: CatalogSelection?
    private let initialQuickAction: QuickAction
    private let onFinish: ((String) -> Void)?

    @State private var screen: Screen = .actions
    @State private var therapyContext: SearchCatalogResolvedContext?
    @State private var stockUnits: Int = 0
    @State private var baselineUnits: Int = 0
    @State private var deadlineMonthInput: String = ""
    @State private var deadlineYearInput: String = ""
    @State private var errorMessage: String?
    @State private var didApplyInitialQuickAction = false

    private let repository = CatalogSelectionRepository()

    init(
        prefill: CatalogSelection? = nil,
        initialQuickAction: QuickAction = .actions,
        onFinish: ((String) -> Void)? = nil
    ) {
        self.prefill = prefill
        self.initialQuickAction = initialQuickAction
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") {
                            dismiss()
                        }
                    }
                }
        }
        .onAppear {
            prepareDefaultStockInputs()
            performInitialQuickActionIfNeeded()
        }
        .sheet(item: $therapyContext) { target in
            NavigationStack {
                TherapyFormView(
                    medicine: target.medicine,
                    package: target.package,
                    context: target.entry.managedObjectContext ?? PersistenceController.shared.container.viewContext,
                    medicinePackage: target.entry,
                    onSave: {
                        complete(message: "Terapia aggiunta e farmaco inserito nell'armadietto.")
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
        .alert(
            "Errore",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Operazione non riuscita.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let item = prefill {
            switch screen {
            case .actions:
                actionsView(for: item)
            case .stock:
                stockView(for: item)
            }
        } else {
            VStack(spacing: 12) {
                Text("Nessun farmaco selezionato")
                    .foregroundStyle(.secondary)
                Button("Chiudi") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func actionsView(for item: CatalogSelection) -> some View {
        Form {
            Section(header: Text("Farmaco")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(camelCase(item.name))
                        .font(.title3.weight(.semibold))
                    Text(packageSummary(for: item))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Azioni")) {
                Button {
                    addMedicineToCabinet(item)
                } label: {
                    Label("Aggiungi nell'armadietto", systemImage: "pills.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .blue, textColor: .white))

                Button {
                    openStockStep(for: item)
                } label: {
                    Label("Confezione acquistata (\(max(1, item.units)))", systemImage: "shippingbox.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .green, textColor: .white))

                Button {
                    openTherapyForm(for: item)
                } label: {
                    Label("Aggiungi terapia", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .orange, textColor: .white))
            }
        }
    }

    private func stockView(for item: CatalogSelection) -> some View {
        Form {
            Section(header: Text("Scorte")) {
                Stepper(value: $stockUnits, in: 0...9999) {
                    Text("Unità disponibili: \(stockUnits)")
                }
                Text("Unità attuali: \(baselineUnits)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Scadenza")) {
                HStack(spacing: 8) {
                    DeadlineMonthYearField(
                        month: $deadlineMonthInput,
                        year: $deadlineYearInput
                    )
                    .frame(width: 110)

                    Spacer()
                }
                Text("Scadenza: \(deadlineSummaryText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    saveStockStep(item)
                } label: {
                    Label("Salva scorte", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .green, textColor: .white))
            }
        }
    }

    private var title: String {
        switch screen {
        case .actions:
            return prefill.map { camelCase($0.name) } ?? "Aggiungi farmaco"
        case .stock:
            return "Scorte"
        }
    }

    private var deadlineSummaryText: String {
        guard let month = Int(deadlineMonthInput),
              let year = Int(deadlineYearInput),
              (1...12).contains(month),
              (2000...2100).contains(year) else {
            return "Non impostata"
        }
        return String(format: "%02d/%04d", month, year)
    }

    private func addMedicineToCabinet(_ item: CatalogSelection) {
        do {
            try appDataStore.provider.search.addCatalogSelectionToCabinet(item)
            complete(message: "Aggiunto all'armadietto.")
        } catch {
            errorMessage = "Non sono riuscito ad aggiungere il farmaco all'armadietto."
        }
    }

    private func openStockStep(for item: CatalogSelection) {
        if let existing = existingContext(for: item) {
            baselineUnits = appDataStore.provider.medicines.units(for: existing.package)
            syncDeadlineInputs(from: existing.entry)
        } else {
            baselineUnits = 0
            deadlineMonthInput = ""
            deadlineYearInput = ""
        }
        stockUnits = baselineUnits + max(1, item.units)
        screen = .stock
    }

    private func saveStockStep(_ item: CatalogSelection) {
        let parsedDeadline = parseDeadlineInputs()
        guard parsedDeadline.isValid else {
            errorMessage = "Scadenza non valida. Usa formato MM/YYYY."
            return
        }

        do {
            let preparation = try appDataStore.provider.search.prepareCatalogPackageEditor(item)
            try appDataStore.provider.search.applyCatalogStockEditor(
                preparation.context,
                targetUnits: stockUnits,
                deadlineMonth: parsedDeadline.month,
                deadlineYear: parsedDeadline.year
            )
            complete(message: "Confezione aggiunta e scorte aggiornate.")
        } catch {
            errorMessage = "Non sono riuscito ad aggiornare le scorte."
        }
    }

    private func openTherapyForm(for item: CatalogSelection) {
        do {
            therapyContext = try appDataStore.provider.search.prepareCatalogTherapy(item)
        } catch {
            errorMessage = "Non sono riuscito ad aprire il form terapia."
        }
    }

    private func existingContext(for item: CatalogSelection) -> SearchCatalogResolvedContext? {
        guard let snapshot = try? appDataStore.provider.search.fetchSnapshot() else { return nil }
        guard let medicine = existingMedicine(for: item, medicines: snapshot.medicines) else { return nil }
        guard let package = existingPackage(for: item, medicine: medicine) ?? medicine.packages.first else { return nil }

        let matchingEntries = snapshot.medicineEntries.filter {
            !$0.isDeleted
                && $0.medicine.id == medicine.id
                && $0.package.id == package.id
        }

        let entry = matchingEntries.max {
            let lhsDate = $0.created_at ?? .distantPast
            let rhsDate = $1.created_at ?? .distantPast
            if lhsDate == rhsDate {
                return $0.id.uuidString < $1.id.uuidString
            }
            return lhsDate < rhsDate
        } ?? medicine.medicinePackages?.first(where: { $0.package.id == package.id })

        guard let entry else { return nil }
        return SearchCatalogResolvedContext(
            selection: item,
            medicine: medicine,
            package: package,
            entry: entry
        )
    }

    private func complete(message: String) {
        onFinish?(message)
        dismiss()
    }

    private func prepareDefaultStockInputs() {
        guard let item = prefill else { return }
        if let existing = existingContext(for: item) {
            baselineUnits = appDataStore.provider.medicines.units(for: existing.package)
            syncDeadlineInputs(from: existing.entry)
        } else {
            baselineUnits = 0
            deadlineMonthInput = ""
            deadlineYearInput = ""
        }
        stockUnits = baselineUnits + max(1, item.units)
    }

    private func performInitialQuickActionIfNeeded() {
        guard !didApplyInitialQuickAction else { return }
        didApplyInitialQuickAction = true
        guard let item = prefill else { return }

        switch initialQuickAction {
        case .actions:
            break
        case .addToCabinet:
            addMedicineToCabinet(item)
        case .addPackage:
            openStockStep(for: item)
        case .addTherapy:
            openTherapyForm(for: item)
        }
    }

    private func syncDeadlineInputs(from entry: MedicinePackage) {
        if let info = entry.deadlineMonthYear {
            deadlineMonthInput = String(format: "%02d", info.month)
            deadlineYearInput = String(info.year)
        } else {
            deadlineMonthInput = ""
            deadlineYearInput = ""
        }
    }

    private func existingMedicine(for selection: CatalogSelection, medicines: [Medicine]) -> Medicine? {
        let identity = repository.identityKey(for: selection)
        if let exact = medicines.first(where: {
            repository.identityKey(name: $0.nome, principle: $0.principio_attivo) == identity
        }) {
            return exact
        }

        let normalizedName = repository.normalizeText(selection.name)
        return medicines.first(where: { repository.normalizeText($0.nome) == normalizedName })
    }

    private func existingPackage(for selection: CatalogSelection, medicine: Medicine) -> Package? {
        medicine.packages.first(where: { packageMatches($0, selection: selection) })
    }

    private func packageMatches(_ package: Package, selection: CatalogSelection) -> Bool {
        let sameUnits = Int(package.numero) == max(1, selection.units)
        let sameType = repository.normalizeText(package.tipologia) == repository.normalizeText(selection.tipologia)
        let sameValue = package.valore == selection.valore
        let sameUnit = repository.normalizeText(package.unita) == repository.normalizeText(selection.unita)
        let sameVolume = repository.normalizeText(package.volume) == repository.normalizeText(selection.volume)
        return sameUnits && sameType && sameValue && sameUnit && sameVolume
    }

    private func parseDeadlineInputs() -> (isValid: Bool, month: Int?, year: Int?) {
        let monthText = deadlineMonthInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearText = deadlineYearInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if monthText.isEmpty && yearText.isEmpty {
            return (true, nil, nil)
        }

        guard let month = Int(monthText),
              let year = Int(yearText),
              (1...12).contains(month),
              (2000...2100).contains(year) else {
            return (false, nil, nil)
        }

        return (true, month, year)
    }

    private func packageSummary(for item: CatalogSelection) -> String {
        var parts: [String] = []
        if item.units > 0 {
            parts.append("\(item.units) unità")
        }
        if !item.tipologia.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(item.tipologia)
        }
        if item.valore > 0 {
            let unit = item.unita.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(unit.isEmpty ? "\(item.valore)" : "\(item.valore) \(unit)")
        }
        if !item.volume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(item.volume)
        }
        return parts.isEmpty ? "Confezione" : parts.joined(separator: " · ")
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
