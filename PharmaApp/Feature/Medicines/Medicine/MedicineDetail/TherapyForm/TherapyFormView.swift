//
//  TherapyFormView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 16/01/25.
//

import SwiftUI
import CoreData

// MARK: - Frequenza supportata
/// Ora abbiamo solo due tipi: Giornaliera o In giorni specifici
enum FrequencyType: String, CaseIterable {
    case daily        = "Giornaliera" // Sostituisce "A intervalli regolari"
    case specificDays = "In giorni specifici" // Settimana personalizzata
    case cycle        = "Ciclica" // Giorni ON/OFF
    
    var label: String {
        switch self {
        case .daily:
            return "Giornaliera"
        case .specificDays:
            return "In giorni specifici"
        case .cycle:
            return "Ciclica"
        }
    }
}

enum TaperDosePreset: String, CaseIterable, Identifiable {
    case full
    case reduce25
    case reduce50
    case reduce75
    case stop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: return "Dose piena"
        case .reduce25: return "Riduci 25%"
        case .reduce50: return "Riduci 50%"
        case .reduce75: return "Riduci 75%"
        case .stop: return "Sospendi"
        }
    }

    static func from(label: String) -> TaperDosePreset {
        Self.allCases.first(where: { $0.label == label }) ?? .full
    }
}

struct TaperStepDraft: Identifiable, Equatable {
    let id: UUID
    var durationDays: Int
    var dosagePreset: TaperDosePreset
}

struct TherapyFormView: View {
    
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appViewModel: AppViewModel
    @FetchRequest(
        entity: Person.entity(),
        sortDescriptors: [NSSortDescriptor(key: "nome", ascending: true)]
    ) private var persons: FetchedResults<Person>
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    
    // Nuovo state per la persona selezionata
    @State private var selectedPerson: Person?
    
    // MARK: - Modello
    var medicine: Medicine
    var package: Package
    var medicinePackage: MedicinePackage?
    
    // Aggiunta per supportare la modifica: se valorizzata, la vista si popola con questa terapia
    var editingTherapy: Therapy?
    var onSave: (() -> Void)?
    var isEmbedded: Bool = false
    
    // MARK: - ViewModel
    @StateObject var therapyFormViewModel: TherapyFormViewModel
    
    // MARK: - Stato Frequenza
    @State private var selectedFrequencyType: FrequencyType = .daily
    
    /// Se l’utente sceglie giornaliera, freq = "DAILY".
    /// Se sceglie giorni specifici, freq = "WEEKLY" con byDay personalizzati.
    @State private var freq: String = "DAILY"
    
    // byDay è utile solo per “in giorni specifici”
    @State private var byDay: [String] = ["MO"]  // Lunedì di default
    
    // useUntil: durata in giorni (course). useCount: numero assunzioni.
    @State private var useUntil: Bool = false
    @State private var untilDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 30)
    @State private var useCount: Bool = false
    @State private var countNumber: Int = 1
    @State private var interval: Int = 1
    @State private var cycleOnDays: Int = 7
    @State private var cycleOffDays: Int = 21
    @State private var therapyDescriptionText: String = ""
    @State private var lastAutoDescriptionText: String = ""
    @State private var recurrenceInput: String = ""
    @State private var lastAutoRecurrenceText: String = ""
    @State private var isRecurrenceValid: Bool = false
    @State private var doseUnit: String = "compressa"
    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())

    // MARK: - Clinical rules (optional)
    @State private var courseEnabled: Bool = false
    @State private var courseTotalDays: Int = 7
    @State private var taperEnabled: Bool = false
    @State private var taperSteps: [TaperStepDraft] = []
    @State private var showTaperEditor: Bool = false

    @State private var interactionsEnabled: Bool = false
    @State private var spacingSubstances: Set<SpacingSubstance> = []
    @State private var spacingHours: Int = 2

    @State private var monitoringEnabled: Bool = false
    @State private var monitoringKind: MonitoringKind = .bloodPressure
    @State private var monitoringDoseRelation: MonitoringDoseRelation = .beforeDose
    @State private var monitoringOffsetMinutes: Int = 30
    @State private var missedDosePreset: MissedDosePreset = .none
    private let showClinicalRuleControls = false

    private var manualIntakeEnabled: Bool {
        options.first?.manual_intake_registration ?? false
    }
    
    // Sezione Orari: con pulsante + per aggiungere e - per rimuovere
    @State private var doses: [DoseEntry] = [DoseEntry(time: Date(), amount: 1)]
    @State private var isShowingDurationSheet = false
    @State private var isShowingMonitoringSheet = false
    
    // MARK: - Init
    init(
        medicine: Medicine,
        package: Package,
        context: NSManagedObjectContext,
        medicinePackage: MedicinePackage? = nil,
        editingTherapy: Therapy? = nil,
        onSave: (() -> Void)? = nil,
        isEmbedded: Bool = false
    ) {
        self.medicine = medicine
        self.package = package
        self.medicinePackage = medicinePackage
        self.editingTherapy = editingTherapy
        self.onSave = onSave
        self.isEmbedded = isEmbedded
        _therapyFormViewModel = StateObject(
            wrappedValue: TherapyFormViewModel(context: context)
        )
    }
    
    var body: some View {
        Group {
            if isEmbedded {
                therapyForm
            } else {
                NavigationView {
                    therapyForm
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Annulla") {
                                    dismiss()
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Salva") {
                                    if shouldParseDescriptionText {
                                        applyTherapyDescription(therapyDescriptionText)
                                    }
                                    saveTherapy()
                                }
                                .disabled(!canSave)
                            }
                        }
                }
            }
        }
    }

    private var therapyForm: some View {
        Form {
            Section(header: Text("Frequenza")) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Es: ogni giorno / lunedì, mercoledì / 7 giorni terapia, 21 giorni pausa", text: $recurrenceInput)
                            .multilineTextAlignment(.leading)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: recurrenceInput) { newValue in
                                applyRecurrenceInput(newValue)
                            }
                        Divider()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isRecurrenceValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .listRowBackground(Color(.systemGroupedBackground))

            Section(header: Text("Orari")) {
                ForEach(doses.indices, id: \.self) { index in
                    HStack {
                        DatePicker("", selection: $doses[index].time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Stepper(value: $doses[index].amount, in: 0.5...12, step: 0.5) {
                            Text(doseDisplayText(amount: doses[index].amount, unit: doseUnitLabel))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { doses.remove(at: index) } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    doses.append(DoseEntry(time: Date(), amount: defaultDoseAmount))
                } label: {
                    Label("Aggiungi un orario", systemImage: "plus.circle")
                }
            }
            .listRowBackground(Color(.systemGroupedBackground))

            Section(header: Text("Durata e inizio")) {
                DatePicker(
                    "Inizio",
                    selection: Binding(
                        get: { startDate },
                        set: { startDate = Calendar.current.startOfDay(for: $0) }
                    ),
                    displayedComponents: .date
                )
                Button {
                    isShowingDurationSheet = true
                } label: {
                    HStack {
                        Text("Fine")
                        Spacer()
                        Text(durationSummaryText)
                            .foregroundColor(.blue)
                    }
                }
                .accessibilityLabel("Seleziona fine terapia")
            }
            .listRowBackground(Color(.systemGroupedBackground))

            Section(header: Text("Persona")) {
                Picker("Seleziona Persona", selection: $selectedPerson) {
                    ForEach(persons, id: \.self) { person in
                        Text(person.nome ?? "")
                            .tag(person as Person?)
                    }
                }
                .accessibilityIdentifier("PersonPicker")
            }
            .listRowBackground(Color(.systemGroupedBackground))

            // Temporaneamente nascosto: accesso impostazioni monitoraggi nel Therapy Form.
            // monitoringOverviewSection

            if showClinicalRuleControls {
                taperSection
                missedDoseSection
            }

            if isEmbedded {
                Section {
                    Button {
                        if shouldParseDescriptionText {
                            applyTherapyDescription(therapyDescriptionText)
                        }
                        saveTherapy()
                    } label: {
                        Label("Salva terapia", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleActionButtonStyle(fill: .green, textColor: .white))
                    .disabled(!canSave)
                }
                .listRowBackground(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(navigationTitleText)
                        .font(.headline)
                    Text(packageSubtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            startDate = startDateToday
            // Edit: popola dai dati della therapy
            if let therapy = editingTherapy {
                populateFromTherapy(therapy)
                selectedPerson = therapy.person
            } else {
                // Edge case: se esiste una sola therapy per questa medicina, assumiamo modalità "edit" implicita
                if selectedPerson == nil {
                    let all = medicine.therapies as? Set<Therapy> ?? []
                    let candidates: [Therapy] = {
                        if let entry = medicinePackage {
                            if let entryTherapies = entry.therapies, !entryTherapies.isEmpty {
                                return Array(entryTherapies)
                            }
                            return all.filter { $0.medicinePackage == entry || $0.package == entry.package }
                        }
                        return all.filter { $0.package == package }
                    }()
                    if candidates.count == 1, let only = candidates.first {
                        populateFromTherapy(only)
                        selectedPerson = only.person
                    } else {
                        selectedPerson = persons.first
                    }
                }
            }
            updateRecurrenceInputIfNeeded(force: true)
        }
        .onChange(of: selectedFrequencyType) { _ in
            updateRecurrenceInputIfNeeded(force: false)
        }
        .onChange(of: interval) { _ in
            updateRecurrenceInputIfNeeded(force: false)
        }
        .onChange(of: cycleOnDays) { _ in
            updateRecurrenceInputIfNeeded(force: false)
        }
        .onChange(of: cycleOffDays) { _ in
            updateRecurrenceInputIfNeeded(force: false)
        }
        .onChange(of: startDate) { _ in
            if courseEnabled {
                syncCourseUntilFromCourse()
            }
        }
        .onChange(of: byDay) { _ in
            updateRecurrenceInputIfNeeded(force: false)
        }
        .sheet(isPresented: $isShowingDurationSheet) {
            NavigationView {
                DurationSelectionView(
                    startDate: baseStartDate,
                    courseEnabled: $courseEnabled,
                    courseTotalDays: $courseTotalDays,
                    useUntil: $useUntil,
                    untilDate: $untilDate,
                    useCount: $useCount,
                    countNumber: $countNumber
                ) {
                    isShowingDurationSheet = false
                }
            }
        }
        // Temporaneamente nascosto: sheet impostazioni monitoraggi nel Therapy Form.
        /*
        .sheet(isPresented: $isShowingMonitoringSheet) {
            NavigationStack {
                Form {
                    monitoringSection
                }
                .navigationTitle("Monitoraggi")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { isShowingMonitoringSheet = false }
                    }
                }
            }
        }
        */
        .sheet(isPresented: $showTaperEditor) {
            NavigationStack {
                TaperStepEditorView(steps: $taperSteps)
            }
        }
    }

    private var navigationTitleText: String {
        camelCase(medicine.nome)
    }

    private var packageSubtitleText: String {
        let typeRaw = package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity: String? = {
            if package.numero > 0 {
                let unitLabel = typeRaw.isEmpty ? "unità" : typeRaw.lowercased()
                return "\(package.numero) \(unitLabel)"
            }
            return typeRaw.isEmpty ? nil : typeRaw.capitalized
        }()
        let dosage: String? = {
            guard package.valore > 0 else { return nil }
            let unit = package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
            return unit.isEmpty ? "\(package.valore)" : "\(package.valore) \(unit)"
        }()
        if let quantity, let dosage {
            return "\(quantity) da \(dosage)"
        }
        if let quantity { return quantity }
        if let dosage { return dosage }
        return "Confezione"
    }

    private func camelCase(_ text: String) -> String {
        let lowered = text.lowercased()
        return lowered
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    private var canSave: Bool {
        // Persona obbligatoria
        guard let _ = selectedPerson else { return false }
        // In edit sempre abilitato; in creazione abilitiamo comunque perché la logica di save evita duplicati aggiornando.
        return true
    }

    private var monitoringStatusText: String {
        monitoringEnabled ? "Attivi" : "Non richiesti"
    }

    private var monitoringDetailsText: String {
        guard monitoringEnabled else { return "Nessun monitoraggio richiesto." }
        let relationText = monitoringDoseRelation == .beforeDose ? "prima" : "dopo"
        return "\(monitoringKind.label) • \(monitoringOffsetMinutes) min \(relationText)"
    }

    @ViewBuilder
    private func clinicalRuleRow(
        title: String,
        subtitle: String,
        status: String,
        statusColor: Color,
        details: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func dayName(for icsDay: String) -> String {
        switch icsDay {
            case "MO": return "Lunedì"
            case "TU": return "Martedì"
            case "WE": return "Mercoledì"
            case "TH": return "Giovedì"
            case "FR": return "Venerdì"
            case "SA": return "Sabato"
            case "SU": return "Domenica"
            default:   return icsDay  
        }
    }

    private var doseUnitLabel: String {
        let tipologia = package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tipologia.contains("capsul") { return "capsula" }
        if tipologia.contains("compress") { return "compressa" }
        let unitFallback = package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unitFallback.isEmpty { return unitFallback.lowercased() }
        return doseUnit
    }

    private var commonDoseAmount: Double? {
        let amounts = doses.map { $0.amount }
        guard let first = amounts.first else { return nil }
        let isUniform = amounts.allSatisfy { abs($0 - first) < 0.0001 }
        return isUniform ? first : nil
    }

    private var defaultDoseAmount: Double {
        commonDoseAmount ?? 1
    }

    private func doseDisplayText(amount: Double, unit: String) -> String {
        if amount == 0.5 {
            return "½ \(unit)"
        }
        let isInt = abs(amount.rounded() - amount) < 0.0001
        let numberString: String = {
            if isInt { return String(Int(amount.rounded())) }
            return String(amount).replacingOccurrences(of: ".", with: ",")
        }()
        let unitString: String = {
            guard amount > 1 else { return unit }
            if unit == "compressa" { return "compresse" }
            if unit == "capsula" { return "capsule" }
            return unit
        }()
        return "\(numberString) \(unitString)"
    }

    private var doseSummaryText: String {
        if let amount = commonDoseAmount {
            return doseDisplayText(amount: amount, unit: doseUnitLabel)
        }
        return "dosi variabili"
    }

    private var therapyDescriptionSection: some View {
        Section(header: Text("Descrizione terapia")) {
            TextField(
                "Es: Per Mattia 1 compressa ogni giorno alle 20:06, chiedi conferma",
                text: $therapyDescriptionText,
                axis: .vertical
            )
            .lineLimit(2...6)
            .onChange(of: therapyDescriptionText) { newValue in
                guard newValue != lastAutoDescriptionText else { return }
                applyTherapyDescription(newValue)
            }
        }
        .listRowBackground(Color(.systemGroupedBackground))
        .onAppear {
            updateTherapyDescriptionIfNeeded(force: true)
        }
        .onChange(of: therapyDescriptionSummaryText) { _ in
            updateTherapyDescriptionIfNeeded(force: false)
        }
    }

    private var durationSection: some View {
        Section(header: Text("Durata")) {
            Button {
                isShowingDurationSheet = true
            } label: {
                HStack {
                    Text("Fine")
                    Spacer()
                    Text(durationSummaryText)
                        .foregroundColor(.blue)
                }
            }
            .accessibilityLabel("Seleziona fine terapia")
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private var monitoringOverviewSection: some View {
        Section(
            header: Text("Monitoraggi"),
            footer: Text("Se attivi, crea un promemoria prima o dopo ogni dose.")
        ) {
            Button {
                isShowingMonitoringSheet = true
            } label: {
                clinicalRuleRow(
                    title: "Monitoraggi",
                    subtitle: "Controlli dose-correlati (es. pressione, glicemia).",
                    status: monitoringStatusText,
                    statusColor: monitoringEnabled ? .blue : .secondary,
                    details: monitoringDetailsText
                )
            }
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private var taperSection: some View {
        Section(header: Text("Scala")) {
            Toggle("Scala (taper)", isOn: $taperEnabled)
            if taperEnabled {
                Button("Configura step") { showTaperEditor = true }
                    .buttonStyle(.bordered)
                if !taperSteps.isEmpty {
                    Text("Step configurati: \(taperSteps.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private var interactionsSection: some View {
        Section(header: Text("Interazioni operative")) {
            Toggle("Distanza da…", isOn: $interactionsEnabled)
            if interactionsEnabled {
                ForEach(SpacingSubstance.allCases, id: \.self) { substance in
                    Toggle(substance.label, isOn: spacingBinding(for: substance))
                }
                Stepper("Distanza \(spacingHours) ore", value: $spacingHours, in: 1...24)
            }
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private var missedDoseSection: some View {
        Section(
            header: Text("Dose mancata"),
            footer: Text("Questa indicazione viene mostrata quando una dose non risulta registrata.")
        ) {
            Picker("Se salti una dose", selection: $missedDosePreset) {
                ForEach(MissedDosePreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.menu)

            if let policy = missedDosePreset.policy, case let .info(title, text) = policy {
                VStack(alignment: .leading, spacing: 4) {
                    if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private var monitoringSection: some View {
        Section(
            header: Text("Monitoraggi"),
            footer: Text("Configura un monitoraggio prima o dopo la dose, con offset libero in minuti.")
        ) {
            Toggle("Richiedi un monitoraggio legato alla dose", isOn: $monitoringEnabled)
            if monitoringEnabled {
                Picker("Cosa controllare", selection: $monitoringKind) {
                    ForEach(MonitoringKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                Picker("Quando", selection: $monitoringDoseRelation) {
                    ForEach(MonitoringDoseRelation.allCases, id: \.self) { relation in
                        Text(relation.label).tag(relation)
                    }
                }

                TextField("Minuti", value: $monitoringOffsetMinutes, format: .number)
                    .keyboardType(.numberPad)

                Text(
                    monitoringDoseRelation == .beforeDose
                    ? "Promemoria: \(monitoringOffsetMinutes) min prima della dose."
                    : "Promemoria: \(monitoringOffsetMinutes) min dopo la dose."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: monitoringOffsetMinutes) { newValue in
            if newValue < 0 {
                monitoringOffsetMinutes = 0
            }
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private func spacingBinding(for substance: SpacingSubstance) -> Binding<Bool> {
        Binding(
            get: { spacingSubstances.contains(substance) },
            set: { isSelected in
                if isSelected {
                    spacingSubstances.insert(substance)
                } else {
                    spacingSubstances.remove(substance)
                }
            }
        )
    }

    private var selectedPersonName: String? {
        guard let selectedPerson else { return nil }
        let first = (selectedPerson.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? nil : first
    }

    private var frequencySummaryText: String {
        switch selectedFrequencyType {
        case .daily:
            if interval == 1 { return "Ogni giorno" }
            return "Ogni \(interval) giorni"
        case .specificDays:
            let dayNames = byDay.map { dayName(for: $0) }
            return dayNames.isEmpty ? "In giorni specifici" : dayNames.joined(separator: ", ")
        case .cycle:
            return "\(cycleOnDays) giorni di terapia, \(cycleOffDays) giorni di pausa"
        }
    }

    private var durationSummaryText: String {
        if useCount {
            let unit = countNumber == 1 ? "assunzione" : "assunzioni"
            return "Dopo \(countNumber) \(unit)"
        }
        if courseEnabled, let endDate = courseEndDate(from: baseStartDate, totalDays: courseTotalDays) {
            if Calendar.current.isDateInToday(endDate) {
                return "Oggi"
            }
            return endDate.formatted(date: .abbreviated, time: .omitted)
        }
        return "Mai"
    }

    private var timesDescriptionText: String? {
        guard !doses.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let includeAmounts = commonDoseAmount == nil
        let sorted = doses.sorted { $0.time < $1.time }
        let segments: [String] = sorted.map { entry in
            let timeText = formatter.string(from: entry.time)
            if includeAmounts {
                let amountText = doseDisplayText(amount: entry.amount, unit: doseUnitLabel)
                return "alle \(timeText) (\(amountText))"
            }
            return "alle \(timeText)"
        }
        guard !segments.isEmpty else { return nil }
        if segments.count == 1 { return segments[0] }
        if segments.count == 2 { return "\(segments[0]) e \(segments[1])" }
        let prefix = segments.dropLast().joined(separator: ", ")
        return "\(prefix) e \(segments.last!)"
    }

    private var therapyDescriptionSummaryText: String {
        var parts: [String] = []
        if let personName = selectedPersonName, !personName.isEmpty {
            parts.append("Per \(personName)")
        }
        parts.append(doseSummaryText)
        parts.append(frequencySummaryText)
        if let timesText = timesDescriptionText {
            parts.append(timesText)
        }
        let confirmation = manualIntakeEnabled ? "chiedi conferma" : "senza conferma"
        if parts.isEmpty {
            return confirmation
        }
        return "\(parts.joined(separator: " ")), \(confirmation)"
    }

    private var shouldParseDescriptionText: Bool {
        let trimmed = therapyDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != lastAutoDescriptionText
    }

    private func updateTherapyDescriptionIfNeeded(force: Bool) {
        let summary = therapyDescriptionSummaryText
        let trimmed = therapyDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty { return }
        if force || trimmed.isEmpty || therapyDescriptionText == lastAutoDescriptionText {
            if therapyDescriptionText != summary {
                therapyDescriptionText = summary
            }
            lastAutoDescriptionText = summary
        }
    }

    private func applyRecurrenceInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isRecurrenceValid = false
            return
        }

        let parser = TherapyDescriptionParser(persons: Array(persons), defaultPerson: persons.first)
        guard let frequency = parser.parseFrequencyOnly(trimmed),
              isAllowedFrequency(frequency) else {
            isRecurrenceValid = false
            return
        }

        switch frequency {
        case .daily(let intervalDays):
            selectedFrequencyType = .daily
            freq = "DAILY"
            interval = max(1, intervalDays)
        case .weekly(let weekDays):
            selectedFrequencyType = .specificDays
            freq = "WEEKLY"
            byDay = weekDays
        case .cycle(let onDays, let offDays):
            selectedFrequencyType = .cycle
            freq = "DAILY"
            interval = 1
            byDay = []
            cycleOnDays = onDays
            cycleOffDays = offDays
        }
        isRecurrenceValid = true
    }

    private func isAllowedFrequency(_ frequency: ParsedTherapyDescription.Frequency) -> Bool {
        switch frequency {
        case .daily(let intervalDays):
            return (1...30).contains(intervalDays)
        case .weekly(let weekDays):
            let allowed = Set(["MO", "TU", "WE", "TH", "FR", "SA", "SU"])
            return !weekDays.isEmpty && weekDays.allSatisfy { allowed.contains($0) }
        case .cycle(let onDays, let offDays):
            return (1...365).contains(onDays) && (1...365).contains(offDays)
        }
    }

    private func updateRecurrenceInputIfNeeded(force: Bool) {
        let summary = frequencySummaryText
        let trimmed = recurrenceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty { return }
        if force || trimmed.isEmpty || recurrenceInput == lastAutoRecurrenceText {
            if recurrenceInput != summary {
                recurrenceInput = summary
            }
            lastAutoRecurrenceText = summary
            isRecurrenceValid = true
        }
    }

    private var startDateToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var baseStartDate: Date {
        Calendar.current.startOfDay(for: startDate)
    }

    private func inclusiveDayCount(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        if selectedFrequencyType != .cycle || cycleOnDays <= 0 || cycleOffDays <= 0 {
            let diff = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
            return max(1, diff + 1)
        }

        var count = 0
        var cursor = startDay
        while cursor <= endDay {
            if isCycleOnDay(cursor, startDay: startDay) {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return max(1, count)
    }

    private func courseEndDate(from start: Date, totalDays: Int) -> Date? {
        let offset = max(0, totalDays - 1)
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        guard selectedFrequencyType == .cycle,
              cycleOnDays > 0,
              cycleOffDays > 0 else {
            return calendar.date(byAdding: .day, value: offset, to: startDay)
        }

        var remaining = max(1, totalDays)
        var cursor = startDay
        while remaining > 0 {
            if isCycleOnDay(cursor, startDay: startDay) {
                remaining -= 1
                if remaining == 0 { return cursor }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return nil
    }

    private func isCycleOnDay(_ day: Date, startDay: Date) -> Bool {
        guard cycleOnDays > 0, cycleOffDays > 0 else { return true }
        let calendar = Calendar.current
        let daySOD = calendar.startOfDay(for: day)
        let diff = calendar.dateComponents([.day], from: startDay, to: daySOD).day ?? 0
        if diff < 0 { return false }
        let cycleLength = cycleOnDays + cycleOffDays
        guard cycleLength > 0 else { return true }
        let dayIndex = diff % cycleLength
        return dayIndex < cycleOnDays
    }

    private func syncCourseUntilFromCourse() {
        guard courseEnabled else { return }
        useUntil = true
        useCount = false
        if let endDate = courseEndDate(from: baseStartDate, totalDays: courseTotalDays) {
            untilDate = endDate
        }
    }

    private func applyTherapyDescription(_ text: String) {
        let parser = TherapyDescriptionParser(persons: Array(persons), defaultPerson: persons.first)
        let parsed = parser.parse(text)

        if let person = parsed.person {
            selectedPerson = person
        }

        var parsedDoseAmount: Double?
        if let dose = parsed.dose {
            parsedDoseAmount = dose.amount
            doseUnit = dose.unit
        }

        if let frequency = parsed.frequency {
            switch frequency {
            case .daily(let intervalDays):
                selectedFrequencyType = .daily
                freq = "DAILY"
                interval = max(1, intervalDays)
            case .weekly(let weekDays):
                selectedFrequencyType = .specificDays
                freq = "WEEKLY"
                byDay = weekDays
            case .cycle(let onDays, let offDays):
                selectedFrequencyType = .cycle
                freq = "DAILY"
                interval = 1
                byDay = []
                cycleOnDays = onDays
                cycleOffDays = offDays
            }
        }

        if let parsedTimes = parsed.times, !parsedTimes.isEmpty {
            let amount = parsedDoseAmount ?? commonDoseAmount ?? 1
            doses = parsedTimes.map { DoseEntry(time: $0, amount: amount) }
        } else if let parsedDoseAmount {
            doses = doses.map { entry in
                DoseEntry(id: entry.id, time: entry.time, amount: parsedDoseAmount)
            }
        }

        if let duration = parsed.duration {
            let calendar = Calendar.current
            let base = baseStartDate
            var totalDays = 0
            switch duration.unit {
            case .days:
                totalDays = duration.value
            case .weeks:
                totalDays = duration.value * 7
            case .months:
                if let until = calendar.date(byAdding: .month, value: duration.value, to: base) {
                    totalDays = inclusiveDayCount(from: base, to: until)
                }
            }
            if totalDays > 0 {
                courseEnabled = true
                courseTotalDays = totalDays
                syncCourseUntilFromCourse()
            }
        }
    }

    private func buildClinicalRules() -> ClinicalRules? {
        let course: CoursePlan? = (courseEnabled && !useCount) ? CoursePlan(totalDays: courseTotalDays) : nil

        let taper: TaperPlan? = {
            guard taperEnabled, !taperSteps.isEmpty else { return nil }
            let steps = taperSteps.map { draft in
                TaperStep(startDate: nil, durationDays: draft.durationDays, dosageLabel: draft.dosagePreset.label)
            }
            return steps.isEmpty ? nil : TaperPlan(steps: steps)
        }()

        let interactions: InteractionRules? = {
            guard interactionsEnabled, !spacingSubstances.isEmpty else { return nil }
            let rules = spacingSubstances.sorted(by: { $0.rawValue < $1.rawValue }).map { substance in
                SpacingRule(substance: substance, hours: spacingHours, direction: nil)
            }
            return InteractionRules(spacing: rules)
        }()

        var monitoringActions = (editingTherapy?.clinicalRulesValue?.monitoring ?? [])
        monitoringActions.removeAll(where: { $0.schedule == nil })
        if monitoringEnabled {
            monitoringActions.append(
                MonitoringAction(
                    kind: monitoringKind,
                    doseRelation: monitoringDoseRelation,
                    offsetMinutes: monitoringOffsetMinutes,
                    requiredBeforeDose: monitoringDoseRelation == .beforeDose,
                    schedule: nil,
                    leadMinutes: monitoringOffsetMinutes
                )
            )
        }
        let monitoring: [MonitoringAction]? = monitoringActions.isEmpty ? nil : monitoringActions

        let missedDosePolicy: MissedDosePolicy? = missedDosePreset.policy

        let rules = ClinicalRules(
            safety: nil,
            course: course,
            taper: taper,
            interactions: interactions,
            monitoring: monitoring,
            missedDosePolicy: missedDosePolicy
        )

        let hasAnyRule = course != nil ||
            taper != nil ||
            interactions != nil ||
            monitoring != nil ||
            missedDosePolicy != nil

        return hasAnyRule ? rules : nil
    }

    private func applyClinicalRules(_ rules: ClinicalRules?) {
        guard let rules else {
            resetClinicalState()
            return
        }

        courseEnabled = rules.course != nil
        courseTotalDays = rules.course?.totalDays ?? courseTotalDays

        taperEnabled = rules.taper != nil
        taperSteps = rules.taper?.steps.map { step in
            TaperStepDraft(
                id: UUID(),
                durationDays: step.durationDays ?? 7,
                dosagePreset: TaperDosePreset.from(label: step.dosageLabel)
            )
        } ?? []

        let spacing = rules.interactions?.spacing ?? []
        interactionsEnabled = !spacing.isEmpty
        spacingSubstances = Set(spacing.map { $0.substance })
        spacingHours = spacing.first?.hours ?? spacingHours

        if let action = rules.monitoring?.first(where: { $0.schedule == nil }) {
            monitoringEnabled = true
            monitoringKind = action.kind
            monitoringDoseRelation = action.resolvedDoseRelation
            monitoringOffsetMinutes = action.resolvedOffsetMinutes
        } else {
            monitoringEnabled = false
        }

        missedDosePreset = MissedDosePreset.from(policy: rules.missedDosePolicy)
    }

    private func resetClinicalState() {
        courseEnabled = false
        courseTotalDays = 7
        taperEnabled = false
        taperSteps = []
        interactionsEnabled = false
        spacingSubstances = []
        spacingHours = 2
        monitoringEnabled = false
        monitoringKind = .bloodPressure
        monitoringDoseRelation = .beforeDose
        monitoringOffsetMinutes = 30
        missedDosePreset = .none
    }
}

// MARK: - Salvataggio e Caricamento

extension TherapyFormView {
    
    private func saveTherapy() {
        if courseEnabled && !useCount {
            syncCourseUntilFromCourse()
        }

        let effectiveStartDate = baseStartDate
        let effectiveImportance = editingTherapy?.importance ?? "standard"
        let clinicalRules = buildClinicalRules()
        let effectivePackage = editingTherapy?.package ?? package
        let effectiveMedicinePackage = medicinePackage ?? editingTherapy?.medicinePackage

        let isCycle = selectedFrequencyType == .cycle
        let effectiveFreq = selectedFrequencyType == .specificDays ? "WEEKLY" : "DAILY"
        let effectiveByDay = selectedFrequencyType == .specificDays ? byDay : []
        let effectiveInterval = isCycle ? 1 : interval
        let cycleOn = isCycle ? cycleOnDays : nil
        let cycleOff = isCycle ? cycleOffDays : nil

        // Persona associata: in modifica usa quella della therapy; altrimenti usa selezione/first/crea
        let effectivePerson: Person = {
            if let sel = selectedPerson { return sel }
            if let t = editingTherapy { return t.person }
            if let first = persons.first { return first }
            let newPerson = Person(context: context)
            newPerson.id = UUID()
            newPerson.nome = ""
            newPerson.cognome = nil
            return newPerson
        }()

        // Se stiamo modificando, aggiorna sempre quella therapy
        if let therapyToUpdate = editingTherapy {
            therapyFormViewModel.updateTherapy(
                therapy: therapyToUpdate,
                freq: effectiveFreq,
                interval: effectiveInterval,
                until: useUntil ? untilDate : nil,
                count: useCount ? countNumber : nil,
                byDay: effectiveByDay,
                cycleOnDays: cycleOn,
                cycleOffDays: cycleOff,
                startDate: effectiveStartDate,
                doses: doses,
                package: effectivePackage,
                medicinePackage: effectiveMedicinePackage,
                importance: effectiveImportance,
                person: effectivePerson,
                manualIntake: manualIntakeEnabled,
                clinicalRules: clinicalRules
            )
        } else {
            // In creazione: aggiungi sempre una nuova therapy per la combinazione selezionata.
            therapyFormViewModel.saveTherapy(
                medicine: medicine,
                freq: effectiveFreq,
                interval: effectiveInterval,
                until: useUntil ? untilDate : nil,
                count: useCount ? countNumber : nil,
                byDay: effectiveByDay,
                cycleOnDays: cycleOn,
                cycleOffDays: cycleOff,
                startDate: effectiveStartDate,
                doses: doses,
                package: effectivePackage,
                medicinePackage: effectiveMedicinePackage,
                importance: "standard",
                person: effectivePerson,
                manualIntake: manualIntakeEnabled,
                clinicalRules: clinicalRules
            )
        }

        appViewModel.isSearchIndexPresented = false
        onSave?()
        if !isEmbedded {
            dismiss()
        }
        
        if let success = therapyFormViewModel.successMessage {
            print("Success: \(success)")
        }
        if let error = therapyFormViewModel.errorMessage {
            print("Error: \(error)")
        }
    }
    
    private func populateIfExisting() {
        // Se la medicine ha una therapy già salvata
        if let existingTherapy = medicine.therapies?.first {
            populateFromTherapy(existingTherapy)
            return
        }
        // Oppure la fetch dal ViewModel
        guard let fetchedTherapy = therapyFormViewModel.fetchTherapy(for: medicine) else { return }
        populateFromTherapy(fetchedTherapy)
    }
    
    private func populateFromTherapy(_ therapy: Therapy) {
        startDate = Calendar.current.startOfDay(for: therapy.start_date ?? startDateToday)
        if let rruleString = therapy.rrule, !rruleString.isEmpty {
            let parsedRule = RecurrenceManager(context: context)
                .parseRecurrenceString(rruleString)
            
            freq = parsedRule.freq
            byDay = parsedRule.byDay
            interval = max(1, parsedRule.interval ?? 1)
            cycleOnDays = parsedRule.cycleOnDays ?? cycleOnDays
            cycleOffDays = parsedRule.cycleOffDays ?? cycleOffDays
            
            if let count = parsedRule.count {
                useCount = true
                countNumber = count
                useUntil = false
            } else {
                useCount = false
                if let until = parsedRule.until {
                    useUntil = true
                    untilDate = until
                } else {
                    useUntil = false
                }
            }
            
            if let on = parsedRule.cycleOnDays, let off = parsedRule.cycleOffDays, on > 0, off > 0 {
                selectedFrequencyType = .cycle
                freq = "DAILY"
                interval = 1
                byDay = []
            } else if freq == "DAILY" {
                selectedFrequencyType = .daily
            } else {
                selectedFrequencyType = .specificDays
            }
        } else {

            selectedFrequencyType = .daily
            freq = "DAILY"
        }
        
        if let existingDoses = therapy.doses as? Set<Dose> {
            let sortedDoses = existingDoses.sorted { $0.time < $1.time }
            self.doses = sortedDoses.map { DoseEntry.fromDose($0) }
        } else {
            self.doses = []
        }
        applyClinicalRules(therapy.clinicalRulesValue)

        if useCount {
            courseEnabled = false
            useUntil = false
        } else if courseEnabled {
            syncCourseUntilFromCourse()
        } else if useUntil {
            courseEnabled = true
            courseTotalDays = inclusiveDayCount(from: baseStartDate, to: untilDate)
            syncCourseUntilFromCourse()
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Errore durante il salvataggio del contesto: \(error.localizedDescription)")
        }
    }

}

struct DurationSelectionView: View {
    var startDate: Date
    @Binding var courseEnabled: Bool
    @Binding var courseTotalDays: Int
    @Binding var useUntil: Bool
    @Binding var untilDate: Date
    @Binding var useCount: Bool
    @Binding var countNumber: Int

    var onClose: () -> Void

    private enum DurationMode: String, CaseIterable, Identifiable {
        case none
        case days
        case count

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none:
                return "Mai"
            case .days:
                return "Giorni"
            case .count:
                return "Numero assunzioni"
            }
        }
    }

    private var selectedMode: DurationMode {
        if useCount { return .count }
        if courseEnabled { return .days }
        return .none
    }

    var body: some View {
        Form {
            Section("Fine") {
                durationRow(.none)
                durationRow(.days)
                durationRow(.count)
            }
            .listRowBackground(Color(.systemGroupedBackground))

            if selectedMode == .days {
                daysSectionView
            }

            if selectedMode == .count {
                countSectionView
            }
        }
        .navigationTitle("Durata")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Annulla") {
                    onClose()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Fine") {
                    onClose()
                }
            }
        }
        .onChange(of: courseTotalDays) { _ in
            syncCourseUntilIfNeeded()
        }
    }

    private var daysSectionView: some View {
        let dayLabel = courseTotalDays == 1 ? "giorno" : "giorni"
        return Section("Giorni") {
            Stepper("Durata: \(courseTotalDays) \(dayLabel)", value: $courseTotalDays, in: 1...365)
            if let endDate = courseEndDate {
                Text("Fine il \(endDate.formatted(date: .long, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Calcolato dalla data di inizio.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private var countSectionView: some View {
        return Section("Numero assunzioni") {
            Stepper("Numero assunzioni: \(countNumber)", value: $countNumber, in: 1...100)
            Text("Totale assunzioni pianificate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private func durationRow(_ mode: DurationMode) -> some View {
        Button {
            applyMode(mode)
        } label: {
            HStack {
                Text(mode.label)
                Spacer()
                if selectedMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private func applyMode(_ mode: DurationMode) {
        switch mode {
        case .none:
            courseEnabled = false
            useUntil = false
            useCount = false
        case .days:
            courseEnabled = true
            syncCourseUntil()
        case .count:
            courseEnabled = false
            useUntil = false
            useCount = true
        }
    }

    private var courseEndDate: Date? {
        let start = Calendar.current.startOfDay(for: startDate)
        let offset = max(0, courseTotalDays - 1)
        return Calendar.current.date(byAdding: .day, value: offset, to: start)
    }

    private func syncCourseUntilIfNeeded() {
        guard selectedMode == .days else { return }
        syncCourseUntil()
    }

    private func syncCourseUntil() {
        useUntil = true
        useCount = false
        if let endDate = courseEndDate {
            untilDate = endDate
        }
    }
}

struct TaperStepEditorView: View {
    @Binding var steps: [TaperStepDraft]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("Step")) {
                if steps.isEmpty {
                    Text("Nessuno step configurato.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    ForEach($steps) { $step in
                        VStack(alignment: .leading, spacing: 8) {
                            Stepper("Durata: \(step.durationDays) giorni", value: $step.durationDays, in: 1...30)
                            Picker("Dose", selection: $step.dosagePreset) {
                                ForEach(TaperDosePreset.allCases) { preset in
                                    Text(preset.label).tag(preset)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        steps.remove(atOffsets: offsets)
                    }
                }
            }

            Section {
                Button("Aggiungi step") {
                    steps.append(
                        TaperStepDraft(
                            id: UUID(),
                            durationDays: 7,
                            dosagePreset: .full
                        )
                    )
                }
            }
            .listRowBackground(Color(.systemGroupedBackground))
        }
        .navigationTitle("Scala terapeutica")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                EditButton()
            }
        }
    }
}
