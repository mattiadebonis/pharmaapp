import SwiftUI
import CoreData

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

    private struct CreatedContext: Identifiable {
        let id = UUID()
        let medicine: Medicine
        let package: Package
        let entry: MedicinePackage
    }

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: Medicine.extractMedicines()) private var medicines: FetchedResults<Medicine>

    private let prefill: CatalogSelection?
    private let initialQuickAction: QuickAction
    private let onFinish: ((String) -> Void)?

    @State private var screen: Screen = .actions
    @State private var therapyContext: CreatedContext?
    @State private var stockUnits: Int = 0
    @State private var baselineUnits: Int = 0
    @State private var deadlineMonthInput: String = ""
    @State private var deadlineYearInput: String = ""
    @State private var errorMessage: String?
    @State private var didApplyInitialQuickAction = false

    private var stockService: MedicineStockService {
        MedicineStockService(context: context)
    }

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
                    context: context,
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
                    Label("Aggiungi confezione", systemImage: "shippingbox.fill")
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
                    TextField("MM", text: Binding(
                        get: { deadlineMonthInput },
                        set: { deadlineMonthInput = sanitizeMonthInput($0) }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)

                    Text("/")
                        .foregroundStyle(.secondary)

                    TextField("YYYY", text: Binding(
                        get: { deadlineYearInput },
                        set: { deadlineYearInput = sanitizeYearInput($0) }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)

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
            _ = try resolveOrCreateContext(for: item)
            try saveIfNeeded()
            complete(message: "Aggiunto all'armadietto.")
        } catch {
            errorMessage = "Non sono riuscito ad aggiungere il farmaco all'armadietto."
        }
    }

    private func openStockStep(for item: CatalogSelection) {
        if let existing = existingContext(for: item) {
            baselineUnits = StockService(context: context).units(for: existing.package)
            syncDeadlineInputs(from: existing.medicine)
        } else {
            baselineUnits = 0
            deadlineMonthInput = ""
            deadlineYearInput = ""
        }
        stockUnits = baselineUnits + max(1, item.units)
        screen = .stock
    }

    private func saveStockStep(_ item: CatalogSelection) {
        do {
            let resolved = try resolveOrCreateContext(for: item)
            applyDeadlineInputs(to: resolved.medicine)
            try saveIfNeeded()

            stockService.addPurchase(medicine: resolved.medicine, package: resolved.package)
            stockService.setStockUnits(medicine: resolved.medicine, package: resolved.package, targetUnits: stockUnits)

            complete(message: "Confezione aggiunta e scorte aggiornate.")
        } catch {
            errorMessage = "Non sono riuscito ad aggiornare le scorte."
        }
    }

    private func openTherapyForm(for item: CatalogSelection) {
        do {
            let resolved = try resolveOrCreateContext(for: item)
            try saveIfNeeded()
            therapyContext = resolved
        } catch {
            errorMessage = "Non sono riuscito ad aprire il form terapia."
        }
    }

    private func resolveOrCreateContext(for item: CatalogSelection) throws -> CreatedContext {
        let medicine = existingMedicine(for: item) ?? createMedicine(from: item)
        medicine.in_cabinet = true
        medicine.obbligo_ricetta = medicine.obbligo_ricetta || item.requiresPrescription

        let package = existingPackage(for: medicine, selection: item) ?? createPackage(for: medicine, selection: item)
        let entry = existingEntry(for: medicine, package: package) ?? createEntry(for: medicine, package: package)

        return CreatedContext(medicine: medicine, package: package, entry: entry)
    }

    private func existingContext(for item: CatalogSelection) -> CreatedContext? {
        guard let medicine = existingMedicine(for: item) else { return nil }
        let package = existingPackage(for: medicine, selection: item) ?? medicine.packages.first
        guard let package else { return nil }
        let entry = existingEntry(for: medicine, package: package)
        guard let entry else { return nil }
        return CreatedContext(medicine: medicine, package: package, entry: entry)
    }

    private func existingMedicine(for item: CatalogSelection) -> Medicine? {
        let identity = catalogIdentityKey(name: item.name, principle: item.principle)
        if let exact = medicines.first(where: {
            catalogIdentityKey(name: $0.nome, principle: $0.principio_attivo) == identity
        }) {
            return exact
        }

        let normalizedName = normalize(item.name)
        return medicines.first(where: { normalize($0.nome) == normalizedName })
    }

    private func existingPackage(for medicine: Medicine, selection: CatalogSelection) -> Package? {
        medicine.packages.first(where: { packageMatches($0, selection: selection) })
    }

    private func existingEntry(for medicine: Medicine, package: Package) -> MedicinePackage? {
        medicine.medicinePackages?.first(where: { $0.package.objectID == package.objectID })
    }

    private func packageMatches(_ package: Package, selection: CatalogSelection) -> Bool {
        let sameUnits = Int(package.numero) == max(1, selection.units)
        let sameType = normalize(package.tipologia) == normalize(selection.tipologia)
        let sameValue = package.valore == selection.valore
        let sameUnit = normalize(package.unita) == normalize(selection.unita)
        let sameVolume = normalize(package.volume) == normalize(selection.volume)

        return sameUnits && sameType && sameValue && sameUnit && sameVolume
    }

    private func createMedicine(from item: CatalogSelection) -> Medicine {
        let medicine = Medicine(context: context)
        medicine.id = UUID()
        medicine.source_id = medicine.id
        medicine.visibility = "local"
        medicine.nome = item.name
        medicine.principio_attivo = item.principle
        medicine.obbligo_ricetta = item.requiresPrescription
        medicine.in_cabinet = true
        return medicine
    }

    private func createPackage(for medicine: Medicine, selection: CatalogSelection) -> Package {
        let package = Package(context: context)
        package.id = UUID()
        package.source_id = package.id
        package.visibility = "local"
        package.tipologia = selection.tipologia.isEmpty ? "Confezione" : selection.tipologia
        package.numero = Int32(max(1, selection.units))
        package.unita = selection.unita.isEmpty ? "unita" : selection.unita
        package.volume = selection.volume
        package.valore = max(0, selection.valore)
        package.principio_attivo = selection.principle
        package.medicine = medicine
        medicine.addToPackages(package)
        return package
    }

    private func createEntry(for medicine: Medicine, package: Package) -> MedicinePackage {
        let entry = MedicinePackage(context: context)
        entry.id = UUID()
        entry.created_at = Date()
        entry.source_id = entry.id
        entry.visibility = "local"
        entry.medicine = medicine
        entry.package = package
        entry.cabinet = nil
        medicine.addToMedicinePackages(entry)
        return entry
    }

    private func saveIfNeeded() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func complete(message: String) {
        onFinish?(message)
        dismiss()
    }

    private func prepareDefaultStockInputs() {
        guard let item = prefill else { return }
        if let existing = existingContext(for: item) {
            baselineUnits = StockService(context: context).units(for: existing.package)
            syncDeadlineInputs(from: existing.medicine)
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

    private func syncDeadlineInputs(from medicine: Medicine) {
        if let info = medicine.deadlineMonthYear {
            deadlineMonthInput = String(format: "%02d", info.month)
            deadlineYearInput = String(info.year)
        } else {
            deadlineMonthInput = ""
            deadlineYearInput = ""
        }
    }

    private func applyDeadlineInputs(to medicine: Medicine) {
        let monthText = deadlineMonthInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearText = deadlineYearInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if monthText.isEmpty && yearText.isEmpty {
            medicine.updateDeadline(month: nil, year: nil)
            return
        }

        guard let month = Int(monthText),
              let year = Int(yearText),
              (1...12).contains(month),
              (2000...2100).contains(year) else {
            return
        }

        medicine.updateDeadline(month: month, year: year)
    }

    private func sanitizeMonthInput(_ value: String) -> String {
        String(value.filter { $0.isNumber }.prefix(2))
    }

    private func sanitizeYearInput(_ value: String) -> String {
        String(value.filter { $0.isNumber }.prefix(4))
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

    private func catalogIdentityKey(name: String, principle: String) -> String {
        let normalizedName = normalize(name)
        let normalizedPrinciple = normalize(principle)
        if normalizedPrinciple.isEmpty {
            return normalizedName
        }
        return "\(normalizedName)|\(normalizedPrinciple)"
    }

    private func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let cleaned = folded.replacingOccurrences(
            of: "[^A-Za-z0-9]",
            with: " ",
            options: .regularExpression
        )
        return cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
