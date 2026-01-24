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
    
    var label: String {
        switch self {
        case .daily:
            return "Giornaliera"
        case .specificDays:
            return "In giorni specifici"
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
    @State private var therapyDescriptionText: String = ""
    @State private var lastAutoDescriptionText: String = ""
    @State private var doseAmount: Double = 1
    @State private var doseUnit: String = "compressa"

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
    @State private var monitoringLeadMinutes: Int = 30
    @State private var missedDosePreset: MissedDosePreset = .none
    
    // Sezione Orari: con pulsante + per aggiungere e - per rimuovere
    @State private var times: [Date] = [Date()]
    @State private var isShowingFrequencySheet = false
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
                                    applyTherapyDescription(therapyDescriptionText)
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
            Section(header: Text("Frequenza e durata")) {
                Button {
                    isShowingFrequencySheet = true
                } label: {
                    HStack {
                        Text("Ripetizione")
                        Spacer()
                        Text(frequencyDescription())
                            .foregroundColor(.blue)
                    }
                }
                .accessibilityLabel("Seleziona frequenza")
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

            Section(header: Text("Orari")) {
                VStack {
                    ForEach(times.indices, id: \.self) { index in
                        HStack {
                            DatePicker("", selection: $times[index], displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text(doseDisplayText)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button { times.remove(at: index) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    Button {
                        times.append(Date())
                    } label: {
                        Label("Aggiungi un orario", systemImage: "plus.circle")
                    }
                }
            }

            Section(header: Text("Persona")) {
                Picker("Seleziona Persona", selection: $selectedPerson) {
                    ForEach(persons, id: \.self) { person in
                        Text(person.nome ?? "")
                            .tag(person as Person?)
                    }
                }
                .accessibilityIdentifier("PersonPicker")
            }

            taperSection
            monitoringOverviewSection
            missedDoseSection

            if isEmbedded {
                Section {
                    Button {
                        applyTherapyDescription(therapyDescriptionText)
                        saveTherapy()
                    } label: {
                        Label("Salva terapia", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleActionButtonStyle(fill: .green, textColor: .white))
                    .disabled(!canSave)
                }
            }
        }
        .navigationTitle("\(medicine.nome) • \(package.numero) unità/conf.")
        .onAppear {
            // Edit: popola dai dati della therapy
            if let therapy = editingTherapy {
                populateFromTherapy(therapy)
                selectedPerson = therapy.person
            } else {
                // Edge case: se esiste una sola therapy per questa medicina, assumiamo modalità "edit" implicita
                if selectedPerson == nil {
                    let set = medicine.therapies as? Set<Therapy> ?? []
                    if set.count == 1, let only = set.first {
                        populateFromTherapy(only)
                        selectedPerson = only.person
                    } else {
                        selectedPerson = persons.first
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingFrequencySheet) {
            NavigationView {
                FrequencySelectionView(
                    selectedFrequencyType: $selectedFrequencyType,
                    freq: $freq,
                    byDay: $byDay,
                    interval: $interval
                ) {
                    isShowingFrequencySheet = false
                }
            }
        }
        .sheet(isPresented: $isShowingDurationSheet) {
            NavigationView {
                DurationSelectionView(
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
        .sheet(isPresented: $showTaperEditor) {
            NavigationStack {
                TaperStepEditorView(steps: $taperSteps)
            }
        }
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
        return "\(monitoringKind.label) • \(monitoringLeadMinutes) min prima"
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
    
    private func frequencyDescription() -> String {
        switch selectedFrequencyType {
        case .daily:
            return "Ogni \(interval) \(interval == 1 ? "giorno" : "giorni")"
        case .specificDays:
            let dayNames = byDay.map { dayName(for: $0) }
            if dayNames.isEmpty {
                return "Nessun giorno"
                
            } else {
                return dayNames.joined(separator: ", ")
            }
        }
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

    private var doseDisplayText: String {
        let unit = doseUnit
        if doseAmount == 0.5 {
            return "½ \(unit)"
        }
        let isInt = abs(doseAmount.rounded() - doseAmount) < 0.0001
        let numberString: String = {
            if isInt { return String(Int(doseAmount.rounded())) }
            return String(doseAmount).replacingOccurrences(of: ".", with: ",")
        }()
        let unitString: String = {
            guard doseAmount > 1 else { return unit }
            if unit == "compressa" { return "compresse" }
            if unit == "capsula" { return "capsule" }
            return unit
        }()
        return "\(numberString) \(unitString)"
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
                applyTherapyDescription(newValue)
            }
        }
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
    }

    private var monitoringOverviewSection: some View {
        Section(
            header: Text("Monitoraggi"),
            footer: Text("Se attivi, crea un promemoria prima di ogni dose.")
        ) {
            Button {
                isShowingMonitoringSheet = true
            } label: {
                clinicalRuleRow(
                    title: "Monitoraggi",
                    subtitle: "Controlli prima della dose (es. pressione, glicemia).",
                    status: monitoringStatusText,
                    statusColor: monitoringEnabled ? .blue : .secondary,
                    details: monitoringDetailsText
                )
            }
        }
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
    }

    private var monitoringSection: some View {
        Section(
            header: Text("Monitoraggi"),
            footer: Text("Se attivi, crea un promemoria prima di ogni dose.")
        ) {
            Toggle("Richiedi un monitoraggio prima della dose", isOn: $monitoringEnabled)
            if monitoringEnabled {
                Picker("Cosa controllare", selection: $monitoringKind) {
                    ForEach(MonitoringKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                Picker("Quanto prima", selection: $monitoringLeadMinutes) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                }
                .pickerStyle(.segmented)
                Text("Promemoria: \(monitoringLeadMinutes) min prima della dose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
        }
    }

    private var durationSummaryText: String {
        if useCount {
            let unit = countNumber == 1 ? "assunzione" : "assunzioni"
            return "Dopo \(countNumber) \(unit)"
        }
        if courseEnabled, let endDate = courseEndDate(from: startDateToday, totalDays: courseTotalDays) {
            if Calendar.current.isDateInToday(endDate) {
                return "Oggi"
            }
            return endDate.formatted(date: .abbreviated, time: .omitted)
        }
        return "Mai"
    }

    private var timesDescriptionText: String? {
        guard !times.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return times
            .sorted()
            .map { "alle \(formatter.string(from: $0))" }
            .joined(separator: ", ")
    }

    private var therapyDescriptionSummaryText: String {
        var parts: [String] = []
        if let personName = selectedPersonName, !personName.isEmpty {
            parts.append("Per \(personName)")
        }
        parts.append(doseDisplayText)
        parts.append(frequencySummaryText)
        if let timesText = timesDescriptionText {
            parts.append(timesText)
        }
        let confirmation = medicine.manual_intake_registration ? "chiedi conferma" : "senza conferma"
        if parts.isEmpty {
            return confirmation
        }
        return "\(parts.joined(separator: " ")), \(confirmation)"
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

    private var startDateToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var baseStartDate: Date {
        editingTherapy?.start_date ?? startDateToday
    }

    private func inclusiveDayCount(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let diff = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(1, diff + 1)
    }

    private func courseEndDate(from start: Date, totalDays: Int) -> Date? {
        let offset = max(0, totalDays - 1)
        return Calendar.current.date(byAdding: .day, value: offset, to: start)
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

        if let dose = parsed.dose {
            doseAmount = dose.amount
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
            }
        }

        if let parsedTimes = parsed.times, !parsedTimes.isEmpty {
            times = parsedTimes
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
        monitoringActions.removeAll(where: { $0.requiredBeforeDose })
        if monitoringEnabled {
            monitoringActions.append(
                MonitoringAction(
                    kind: monitoringKind,
                    requiredBeforeDose: true,
                    schedule: nil,
                    leadMinutes: monitoringLeadMinutes
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

        if let action = rules.monitoring?.first(where: { $0.requiredBeforeDose }) {
            monitoringEnabled = true
            monitoringKind = action.kind
            monitoringLeadMinutes = action.leadMinutes ?? monitoringLeadMinutes
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
        monitoringLeadMinutes = 30
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
            if selectedFrequencyType == .daily {
                therapyFormViewModel.updateTherapy(
                    therapy: therapyToUpdate,
                    freq: "DAILY",
                    interval: interval,
                    until: useUntil ? untilDate : nil,
                    count: useCount ? countNumber : nil,
                    byDay: [],
                    startDate: effectiveStartDate,
                    times: times,
                    package: effectivePackage,
                    medicinePackage: effectiveMedicinePackage,
                    importance: effectiveImportance,
                    person: effectivePerson,
                    manualIntake: medicine.manual_intake_registration,
                    clinicalRules: clinicalRules
                )
            } else {
                therapyFormViewModel.updateTherapy(
                    therapy: therapyToUpdate,
                    freq: "WEEKLY",
                    interval: interval,
                    until: useUntil ? untilDate : nil,
                    count: useCount ? countNumber : nil,
                    byDay: byDay,
                    startDate: effectiveStartDate,
                    times: times,
                    package: effectivePackage,
                    medicinePackage: effectiveMedicinePackage,
                    importance: effectiveImportance,
                    person: effectivePerson,
                    manualIntake: medicine.manual_intake_registration,
                    clinicalRules: clinicalRules
                )
            }
        } else {
            // In creazione: aggiungi sempre una nuova therapy per la combinazione selezionata.
            if selectedFrequencyType == .daily {
                therapyFormViewModel.saveTherapy(
                    medicine: medicine,
                    freq: "DAILY",
                    interval: interval,
                    until: useUntil ? untilDate : nil,
                    count: useCount ? countNumber : nil,
                    byDay: [],
                    startDate: effectiveStartDate,
                    times: times,
                    package: effectivePackage,
                    medicinePackage: effectiveMedicinePackage,
                    importance: "standard",
                    person: effectivePerson,
                    manualIntake: medicine.manual_intake_registration,
                    clinicalRules: clinicalRules
                )
            } else {
                therapyFormViewModel.saveTherapy(
                    medicine: medicine,
                    freq: "WEEKLY",
                    interval: interval,
                    until: useUntil ? untilDate : nil,
                    count: useCount ? countNumber : nil,
                    byDay: byDay,
                    startDate: effectiveStartDate,
                    times: times,
                    package: effectivePackage,
                    medicinePackage: effectiveMedicinePackage,
                    importance: "standard",
                    person: effectivePerson,
                    manualIntake: medicine.manual_intake_registration,
                    clinicalRules: clinicalRules
                )
            }
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
        if let rruleString = therapy.rrule, !rruleString.isEmpty {
            let parsedRule = RecurrenceManager(context: context)
                .parseRecurrenceString(rruleString)
            
            freq = parsedRule.freq
            byDay = parsedRule.byDay
            interval = max(1, parsedRule.interval ?? 1)
            
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
            
            if freq == "DAILY" {
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
            self.times = sortedDoses.map { $0.time }
        } else {
            self.times = []
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

// MARK: - Seconda Vista: FrequencySelectionView

struct FrequencySelectionView: View {
    
    @Binding var selectedFrequencyType: FrequencyType
    @Binding var freq: String
    @Binding var byDay: [String]
    @Binding var interval: Int

    var onClose: () -> Void
    let allDaysICS = ["MO","TU","WE","TH","FR","SA","SU"]

    var body: some View {
        Form {
            Section {
                frequencyRow(.daily)
                frequencyRow(.specificDays)
            }
            
            if selectedFrequencyType == .daily {
                dailySectionView
            }
            
            if selectedFrequencyType == .specificDays {
                specificDaysSectionView
            }
        }
        .navigationTitle("Frequenza")
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
    }
    
    // MARK: - Sezioni

   private var dailySectionView: some View {
            
        Section("Scegli intervallo") {
            Picker("Ogni", selection: $interval) {
                ForEach(1..<31) { i in
                    Text("\(i) \(i == 1 ? "giorno" : "giorni")").tag(i)
                }
            }
            .pickerStyle(.wheel)
        }
            
    }
    
    private var specificDaysSectionView: some View {
        Section("In giorni specifici") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allDaysICS, id: \.self) { day in
                        let isSelected = byDay.contains(day)
                        Text(day)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(16)
                            .onTapGesture {
                                toggleDay(day)
                            }
                    }
                }
                .padding(.vertical, 6)
            }
            
        }
    }
    
    // MARK: - Helpers
    
    private func frequencyRow(_ option: FrequencyType) -> some View {
        Button {
            selectedFrequencyType = option
            switch option {
            case .daily:
                freq = "DAILY"
            case .specificDays:
                freq = "WEEKLY"
            }
        } label: {
            HStack {
                Text(option.label)
                Spacer()
                if selectedFrequencyType == option {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    private func toggleDay(_ day: String) {
        if let idx = byDay.firstIndex(of: day) {
            byDay.remove(at: idx)
        } else {
            byDay.append(day)
        }
    }
    
    
}

struct DurationSelectionView: View {
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
            Text("Calcolato da oggi.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var countSectionView: some View {
        return Section("Numero assunzioni") {
            Stepper("Numero assunzioni: \(countNumber)", value: $countNumber, in: 1...100)
            Text("Totale assunzioni pianificate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
        let startDate = Calendar.current.startOfDay(for: Date())
        let offset = max(0, courseTotalDays - 1)
        return Calendar.current.date(byAdding: .day, value: offset, to: startDate)
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
