import SwiftUI
import CoreData

struct MedicineWizardView: View {
    enum Step: Int, CaseIterable {
        case detail
        case therapies
        case stock

        var label: String {
            switch self {
            case .detail: return "Dettaglio"
            case .therapies: return "Terapie"
            case .stock: return "Scorte"
            }
        }
    }

    private struct CatalogItem: Identifiable, Hashable {
        let id: String
        let name: String
        let principle: String
        let requiresPrescription: Bool
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

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>

    @StateObject private var stockViewModel = MedicineFormViewModel(
        context: PersistenceController.shared.container.viewContext
    )
    private let recurrenceManager = RecurrenceManager(
        context: PersistenceController.shared.container.viewContext
    )

    private let prefill: CatalogSelection?
    @State private var didApplyPrefill = false
    @State private var step: Step = .detail
    @State private var selectedItem: CatalogItem?
    @State private var selectedPackage: CatalogPackage?
    @State private var createdMedicine: Medicine?
    @State private var createdPackage: Package?
    @State private var selectedTherapy: Therapy?
    @State private var therapySheetID = UUID()
    @State private var stockUnits: Int = 0
    @State private var wizardDetent: PresentationDetent = .fraction(0.5)
    @State private var stayOnTherapiesAfterSave = false
    @State private var deadlineMonthInput: String = ""
    @State private var deadlineYearInput: String = ""

    init(prefill: CatalogSelection? = nil) {
        self.prefill = prefill
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                wizardHeader
                Divider()
                    .opacity(0.3)
                stepContent
            }
            .navigationTitle(wizardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Indietro") { goBack() }
                }
            }
        }
        .onAppear { applyPrefillIfNeeded() }
        .onChange(of: step) { newStep in
            wizardDetent = defaultDetent(for: newStep)
        }
        .presentationDetents(Set(detentsForCurrentStep), selection: $wizardDetent)
    }

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.self) { item in
                    Button {
                        step = item
                    } label: {
                        Text(item.label)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(step == item ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(step == item ? Color.accentColor : Color(.secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            ProgressView(
                value: Double(step.rawValue + 1),
                total: Double(Step.allCases.count)
            )
            .tint(.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .detail:
            detailStep
        case .therapies:
            therapiesStep
        case .stock:
            stockStep
        }
    }

    private var detentsForCurrentStep: [PresentationDetent] {
        switch step {
        case .detail:
            return [.fraction(0.5), .large]
        case .therapies, .stock:
            return [.medium, .large]
        }
    }

    private func defaultDetent(for step: Step) -> PresentationDetent {
        switch step {
        case .detail: return .fraction(0.5)
        case .therapies, .stock: return .medium
        }
    }

    private var detailStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedItem {
                Form {
                    Section(header: Text("Farmaco")) {
                        Text(selectedItem.name)
                            .font(.headline)
                        Text(selectedItem.principle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if selectedItem.requiresPrescription {
                            Label("Richiede ricetta", systemImage: "stethoscope")
                                .foregroundStyle(.orange)
                                .font(.callout.weight(.semibold))
                        }
                    }

                    Section(header: Text("Confezione")) {
                        if selectedItem.packages.count > 1 {
                            Picker("Formato", selection: Binding(
                                get: { selectedPackage ?? selectedItem.packages.first },
                                set: { newValue in
                                    selectedPackage = newValue
                                }
                            )) {
                                ForEach(selectedItem.packages) { pkg in
                                    Text(pkg.label)
                                        .tag(Optional(pkg))
                                }
                            }
                        } else if let pkg = selectedItem.packages.first {
                            Text(pkg.label)
                                .foregroundStyle(.secondary)
                        }
                        if let pkg = selectedPackage ?? selectedItem.packages.first {
                            Text(packageSummary(pkg))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button {
                            addToCabinet()
                        } label: {
                            Label("Aggiungi all'armadietto", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CapsuleActionButtonStyle(fill: .teal, textColor: .white))
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("Seleziona un farmaco per continuare")
                        .foregroundStyle(.secondary)
                    Button("Indietro") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var therapiesStep: some View {
        Group {
            if let medicine = createdMedicine, let package = createdPackage {
                VStack(spacing: 0) {
                    therapiesPicker
                    TherapyFormView(
                        medicine: medicine,
                        package: package,
                        context: context,
                        editingTherapy: selectedTherapy,
                        onSave: handleTherapySaved,
                        isEmbedded: true
                    )
                    .id(therapySheetID)
                }
                .safeAreaInset(edge: .bottom) {
                    therapiesFooter
                }
            } else {
                placeholderForMissingCreation
            }
        }
    }

    private var stockStep: some View {
        Group {
            if let medicine = createdMedicine, let package = createdPackage {
                Form {
                    Section(header: Text("Confezioni e scorte")) {
                        Stepper(value: $stockUnits, in: 0...400) {
                            Text("\(stockUnits) unità disponibili")
                        }
                        .onChange(of: stockUnits) { newValue in
                            updateStockUnits(to: newValue, medicine: medicine, package: package)
                        }
                        Text("Registra quante unità possiedi ora; aggiungiamo o rimuoviamo log di scorta automaticamente.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section(header: Text("Scadenza")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                TextField("MM", text: Binding(
                                    get: { deadlineMonthInput },
                                    set: { newValue in
                                        let sanitized = sanitizeMonthInput(newValue)
                                        if sanitized != deadlineMonthInput {
                                            deadlineMonthInput = sanitized
                                        }
                                        updateDeadlineFromInputs(for: medicine)
                                    }
                                ))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 50)

                                Text("/")
                                    .foregroundStyle(.secondary)

                                TextField("YYYY", text: Binding(
                                    get: { deadlineYearInput },
                                    set: { newValue in
                                        let sanitized = sanitizeYearInput(newValue)
                                        if sanitized != deadlineYearInput {
                                            deadlineYearInput = sanitized
                                        }
                                        updateDeadlineFromInputs(for: medicine)
                                    }
                                ))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 70)

                                Spacer()
                            }
                            Text("Scadenza attuale: \(deadlineSummaryText(for: medicine))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button {
                            dismiss()
                        } label: {
                            Label("Fine", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CapsuleActionButtonStyle(fill: .green, textColor: .white))
                    }
                }
                .onAppear {
                    stockUnits = currentUnits(for: medicine, package: package)
                    syncDeadlineInputs(from: medicine)
                }
            } else {
                placeholderForMissingCreation
            }
        }
    }

    private var therapiesPicker: some View {
        let therapies = currentTherapies
        return Group {
            if therapies.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button {
                            selectTherapy(nil)
                        } label: {
                            Text("Nuova terapia")
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(selectedTherapy == nil ? Color.accentColor : Color(.secondarySystemBackground)))
                                .foregroundStyle(selectedTherapy == nil ? .white : .primary)
                        }
                        .buttonStyle(.plain)

                        ForEach(therapies, id: \.objectID) { therapy in
                            Button {
                                selectTherapy(therapy)
                            } label: {
                                Text(recurrenceDescription(for: therapy))
                                    .font(.callout.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(selectedTherapy?.objectID == therapy.objectID ? Color.accentColor : Color(.secondarySystemBackground)))
                                    .foregroundStyle(selectedTherapy?.objectID == therapy.objectID ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))
            }
        }
    }

    private var therapiesFooter: some View {
        VStack(spacing: 12) {
            Toggle("Resta su Terapie dopo il salvataggio", isOn: $stayOnTherapiesAfterSave)
                .toggleStyle(.switch)
            Button {
                step = .stock
            } label: {
                Label("Prosegui alle confezioni", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CapsuleActionButtonStyle(fill: .blue, textColor: .white))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(.separator)),
            alignment: .top
        )
    }

    private var placeholderForMissingCreation: some View {
        VStack(spacing: 12) {
            Text("Completa prima il passaggio precedente.")
                .foregroundStyle(.secondary)
            Button("Vai al dettaglio") { step = .detail }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addToCabinet() {
        guard createdMedicine == nil else {
            step = .therapies
            return
        }
        guard let item = selectedItem, let pkg = selectedPackage ?? item.packages.first else {
            return
        }

        let medicine = Medicine(context: context)
        medicine.id = UUID()
        medicine.nome = item.name
        medicine.principio_attivo = item.principle
        medicine.obbligo_ricetta = item.requiresPrescription || pkg.requiresPrescription
        medicine.in_cabinet = true
        let option = options.first
        medicine.custom_stock_threshold = option?.day_threeshold_stocks_alarm ?? Int32(7)
        medicine.manual_intake_registration = true

        let package = Package(context: context)
        package.id = UUID()
        package.tipologia = pkg.tipologia
        package.unita = pkg.dosageUnit
        package.volume = pkg.volume
        package.valore = pkg.dosageValue
        package.numero = Int32(max(1, pkg.units))
        package.medicine = medicine
        medicine.addToPackages(package)

        do {
            try context.save()
            stockViewModel.addPurchase(for: medicine, for: package)
            createdMedicine = medicine
            createdPackage = package
            stockUnits = currentUnits(for: medicine, package: package)
            selectedTherapy = nil
            therapySheetID = UUID()
            step = .therapies
        } catch {
            print("Errore nel salvataggio del medicinale: \(error)")
        }
    }

    private func updateStockUnits(to newValue: Int, medicine: Medicine, package: Package) {
        stockViewModel.setStockUnits(medicine: medicine, package: package, targetUnits: newValue)
    }

    private var currentTherapies: [Therapy] {
        guard let medicine = createdMedicine else { return [] }
        let set = medicine.therapies as? Set<Therapy> ?? []
        return set.sorted { (lhs, rhs) in
            let l = lhs.start_date ?? .distantPast
            let r = rhs.start_date ?? .distantPast
            return l < r
        }
    }

    private func recurrenceDescription(for therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let description = recurrenceManager.describeRecurrence(rule: rule)
        return description.capitalized
    }

    private func nextDose(for therapy: Therapy) -> Date? {
        recurrenceManager.nextOccurrence(
            rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
            startDate: therapy.start_date ?? Date(),
            after: Date(),
            doses: therapy.doses as NSSet?
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        } else if calendar.isDateInTomorrow(date) {
            return "Domani"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func selectTherapy(_ therapy: Therapy?) {
        selectedTherapy = therapy
        therapySheetID = UUID()
    }

    private func refreshCreatedMedicine() {
        guard let med = createdMedicine else { return }
        createdMedicine = try? context.existingObject(with: med.objectID) as? Medicine ?? med
    }

    private func goBack() {
        switch step {
        case .detail:
            dismiss()
        case .therapies:
            step = .detail
        case .stock:
            step = .therapies
        }
    }

    private func handleTherapySaved() {
        refreshCreatedMedicine()
        if selectedTherapy == nil && !stayOnTherapiesAfterSave {
            step = .stock
        } else if selectedTherapy == nil {
            therapySheetID = UUID()
        }
    }

    private func deadlineSummaryText(for medicine: Medicine) -> String {
        medicine.deadlineLabel ?? "Non impostata"
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

    private func sanitizeMonthInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return String(digits.prefix(2))
    }

    private func sanitizeYearInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return String(digits.prefix(4))
    }

    private func clearDeadline(for medicine: Medicine) {
        deadlineMonthInput = ""
        deadlineYearInput = ""
        medicine.updateDeadline(month: nil, year: nil)
        saveContext()
    }

    private func updateDeadlineFromInputs(for medicine: Medicine) {
        let monthText = deadlineMonthInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearText = deadlineYearInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if monthText.isEmpty && yearText.isEmpty {
            clearDeadline(for: medicine)
            return
        }

        guard let month = Int(monthText),
              let year = Int(yearText),
              (1...12).contains(month),
              (2000...2100).contains(year) else {
            return
        }

        medicine.updateDeadline(month: month, year: year)
        saveContext()
    }

    private func saveContext() {
        try? context.save()
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

    private func packageSummary(_ package: CatalogPackage) -> String {
        var parts: [String] = []
        if package.units > 0 {
            parts.append("\(package.units) unità")
        }
        if package.dosageValue > 0 {
            let unit = package.dosageUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("\(package.dosageValue)\(unit.isEmpty ? "" : " \(unit)")")
        }
        if !package.volume.isEmpty {
            parts.append(package.volume)
        }
        return parts.isEmpty ? "Formato non specificato" : parts.joined(separator: " • ")
    }

    private func packageLabel(_ package: Package) -> String {
        let type = package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        let volume = package.volume.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if package.numero > 0 {
            let unitLabel = type.isEmpty ? "unità" : type.lowercased()
            parts.append("\(package.numero) \(unitLabel)")
        } else if !type.isEmpty {
            parts.append(type.capitalized)
        }
        if package.valore > 0 {
            let unitText = unit.isEmpty ? "" : " \(unit)"
            parts.append("\(package.valore)\(unitText)")
        }
        if !volume.isEmpty {
            parts.append(volume)
        }
        let text = parts.joined(separator: " • ")
        return text.isEmpty ? "Confezione" : text
    }

    private func currentUnits(for medicine: Medicine, package: Package) -> Int {
        guard let context = medicine.managedObjectContext ?? package.managedObjectContext else { return 0 }
        let stockService = StockService(context: context)
        return max(0, stockService.units(for: package))
    }

    private func applyPrefillIfNeeded() {
        guard !didApplyPrefill, let prefill else { return }
        let pkg = CatalogPackage(
            id: prefill.id,
            label: prefill.packageLabel.isEmpty ? "Confezione" : prefill.packageLabel,
            units: max(1, prefill.units),
            tipologia: prefill.tipologia.isEmpty ? prefill.packageLabel : prefill.tipologia,
            dosageValue: prefill.valore,
            dosageUnit: prefill.unita,
            volume: prefill.volume,
            requiresPrescription: prefill.requiresPrescription
        )
        let item = CatalogItem(
            id: prefill.id,
            name: prefill.name,
            principle: prefill.principle,
            requiresPrescription: prefill.requiresPrescription,
            packages: [pkg]
        )
        selectedItem = item
        selectedPackage = pkg
        step = .detail
        didApplyPrefill = true
    }

    private func naturalPackageLabel(for package: CatalogPackage) -> String {
        var parts: [String] = []
        if package.units > 0 {
            parts.append("\(package.units) unità")
        }
        if package.dosageValue > 0 {
            let unit = package.dosageUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            let dosage = unit.isEmpty ? "\(package.dosageValue)" : "\(package.dosageValue) \(unit)"
            parts.append(dosage)
        }
        if !package.volume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(package.volume)
        }
        let fallback = package.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if parts.isEmpty { return fallback.isEmpty ? "Confezione" : camelCase(fallback) }
        return parts.joined(separator: " • ")
    }

    private var wizardTitle: String {
        if let med = createdMedicine {
            let name = med.nome.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Nuovo medicinale" : camelCase(name)
        }
        if let item = selectedItem {
            return camelCase(item.name)
        }
        return "Nuovo medicinale"
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
