import SwiftUI
import CoreData

struct MedicineWizardView: View {
    enum Step: Int, CaseIterable {
        case review
        case recurrenceDuration
        case schedule
        case person
        case stock

        var label: String {
            switch self {
            case .review: return "Farmaco"
            case .recurrenceDuration: return "Ripetizione e durata"
            case .schedule: return "Orari"
            case .person: return "Persona"
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

    private struct TherapyDraft {
        var selectedFrequencyType: FrequencyType = .daily
        var byDay: [String] = ["MO"]
        var interval: Int = 1
        var cycleOnDays: Int = 7
        var cycleOffDays: Int = 21

        var useUntil: Bool = false
        var untilDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 30)
        var useCount: Bool = false
        var countNumber: Int = 1

        var doseUnit: String = "compressa"
        var doses: [DoseEntry] = [DoseEntry(time: Date(), amount: 1)]

        var courseEnabled: Bool = false
        var courseTotalDays: Int = 7
        var taperEnabled: Bool = false
        var taperSteps: [TaperStepDraft] = []

        var monitoringEnabled: Bool = false
        var monitoringKind: MonitoringKind = .bloodPressure
        var monitoringLeadMinutes: Int = 30

        var missedDosePreset: MissedDosePreset = .none
        var selectedPerson: Person?
    }

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Person.extractPersons()) private var persons: FetchedResults<Person>

    @StateObject private var therapyFormViewModel = TherapyFormViewModel(
        context: PersistenceController.shared.container.viewContext
    )

    private let prefill: CatalogSelection?
    private let onFinish: (() -> Void)?
    @State private var didApplyPrefill = false
    @State private var step: Step = .review
    @State private var selectedItem: CatalogItem?
    @State private var selectedPackage: CatalogPackage?
    @State private var therapyDraft = TherapyDraft()
    @State private var recurrenceInput: String = ""
    @State private var lastAutoRecurrenceText: String = ""
    @State private var isRecurrenceValid: Bool = false
    @State private var stockUnits: Int = 0
    @State private var wizardDetent: PresentationDetent = .medium
    @State private var deadlineMonthInput: String = ""
    @State private var deadlineYearInput: String = ""
    @State private var showTaperEditor = false

    private var stockService: MedicineStockService {
        MedicineStockService(context: context)
    }

    init(prefill: CatalogSelection? = nil, onFinish: (() -> Void)? = nil) {
        self.prefill = prefill
        self.onFinish = onFinish
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
        .onAppear {
            applyPrefillIfNeeded()
            ensureSelectedPerson()
            updateRecurrenceInputIfNeeded(force: true)
        }
        .onChange(of: step) { newStep in
            wizardDetent = defaultDetent(for: newStep)
        }
        .onChange(of: persons.count) { _ in
            ensureSelectedPerson()
        }
        .presentationDetents(Set(detentsForCurrentStep), selection: $wizardDetent)
    }

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
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
                }
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
        if selectedItem == nil {
            missingSelectionView
        } else {
            switch step {
            case .review:
                reviewStep
            case .recurrenceDuration:
                recurrenceDurationStep
            case .schedule:
                scheduleStep
            case .person:
                personStep
            case .stock:
                stockStep
            }
        }
    }

    private var detentsForCurrentStep: [PresentationDetent] {
        [.medium, .large]
    }

    private func defaultDetent(for step: Step) -> PresentationDetent {
        .medium
    }

    private var reviewStep: some View {
        Form {
            if let item = selectedItem {
                Section(header: Text("Farmaco riconosciuto")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(camelCase(item.name))
                            .font(.title3.weight(.semibold))
                        if !item.principle.isEmpty {
                            Text(item.principle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let pkg = selectedPackage {
                    Section(header: Text("Confezione")) {
                        VStack(alignment: .leading, spacing: 6) {
                            if pkg.units > 0 {
                                Label("\(pkg.units) unità", systemImage: "pills")
                                    .font(.subheadline)
                            }
                            if pkg.dosageValue > 0 {
                                let unit = pkg.dosageUnit.trimmingCharacters(in: .whitespacesAndNewlines)
                                Label(unit.isEmpty ? "\(pkg.dosageValue)" : "\(pkg.dosageValue) \(unit)", systemImage: "scalemass")
                                    .font(.subheadline)
                            }
                            if !pkg.volume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label(pkg.volume, systemImage: "drop")
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        HStack {
                            Text("Ricetta")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(pkg.requiresPrescription ? "Richiesta" : "Non richiesta")
                                .foregroundStyle(pkg.requiresPrescription ? .orange : .green)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }

            Section {
                Button {
                    step = .recurrenceDuration
                } label: {
                    Label("Prosegui alla terapia", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .blue, textColor: .white))
            }
        }
    }

    private var recurrenceDurationStep: some View {
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

            Section(header: Text("Durata")) {
                durationRow(.none)
                durationRow(.days)
                durationRow(.count)
            }

            if selectedDurationMode == .days {
                daysSectionView
            }

            if selectedDurationMode == .count {
                countSectionView
            }

            Section {
                Button {
                    step = .schedule
                } label: {
                    Label("Prosegui agli orari", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .blue, textColor: .white))
            }
        }
        .onChange(of: therapyDraft.courseTotalDays) { _ in
            if selectedDurationMode == .days {
                syncCourseUntilFromCourse()
            }
        }
    }

    private var scheduleStep: some View {
        Form {
            Section(header: Text("Orari")) {
                ForEach(therapyDraft.doses.indices, id: \.self) { index in
                    HStack {
                        DatePicker("", selection: $therapyDraft.doses[index].time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Stepper(value: $therapyDraft.doses[index].amount, in: 0.5...12, step: 0.5) {
                            Text(doseDisplayText(amount: therapyDraft.doses[index].amount, unit: doseUnitLabel))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            therapyDraft.doses.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                Button {
                    therapyDraft.doses.append(DoseEntry(time: Date(), amount: defaultDoseAmount))
                } label: {
                    Label("Aggiungi un orario", systemImage: "plus.circle")
                }
            }

            Section(header: Text("Scala")) {
                Toggle("Scala (taper)", isOn: $therapyDraft.taperEnabled)
                if therapyDraft.taperEnabled {
                    Button("Configura step") { showTaperEditor = true }
                        .buttonStyle(.bordered)
                    if !therapyDraft.taperSteps.isEmpty {
                        Text("Step configurati: \(therapyDraft.taperSteps.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(
                header: Text("Monitoraggi"),
                footer: Text("Se attivi, crea un promemoria prima di ogni dose.")
            ) {
                Toggle("Richiedi un monitoraggio prima della dose", isOn: $therapyDraft.monitoringEnabled)
                if therapyDraft.monitoringEnabled {
                    Picker("Cosa controllare", selection: $therapyDraft.monitoringKind) {
                        ForEach(MonitoringKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    Picker("Quanto prima", selection: $therapyDraft.monitoringLeadMinutes) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                    }
                    .pickerStyle(.segmented)
                    Text("Promemoria: \(therapyDraft.monitoringLeadMinutes) min prima della dose.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    step = .person
                } label: {
                    Label("Prosegui alla persona", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .blue, textColor: .white))
            }
        }
        .sheet(isPresented: $showTaperEditor) {
            NavigationStack {
                TaperStepEditorView(steps: $therapyDraft.taperSteps)
            }
        }
    }

    private var personStep: some View {
        Form {
            Section(header: Text("Persona")) {
                Picker("Seleziona Persona", selection: $therapyDraft.selectedPerson) {
                    ForEach(persons, id: \.self) { person in
                        Text(person.nome ?? "")
                            .tag(person as Person?)
                    }
                }
                .accessibilityIdentifier("PersonPicker")
            }

            Section(
                header: Text("Dose mancata"),
                footer: Text("Questa indicazione viene mostrata quando una dose non risulta registrata.")
            ) {
                Picker("Se salti una dose", selection: $therapyDraft.missedDosePreset) {
                    ForEach(MissedDosePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                if let policy = therapyDraft.missedDosePreset.policy, case let .info(title, text) = policy {
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

            Section {
                Button {
                    step = .stock
                } label: {
                    Label("Prosegui alle scorte", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .blue, textColor: .white))
            }
        }
    }

    private var stockStep: some View {
        Form {
            Section(header: Text("Confezioni e scorte")) {
                Stepper(value: $stockUnits, in: 0...400) {
                    Text("\(stockUnits) unita disponibili")
                }
                Text("Registra quante unita possiedi ora; aggiungiamo o rimuoviamo log di scorta automaticamente.")
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
                            }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 70)

                        Spacer()
                    }
                    Text("Scadenza attuale: \(deadlineSummaryText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    finishWizard()
                } label: {
                    Label("Fine", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionButtonStyle(fill: .green, textColor: .white))
            }
        }
    }

    private var missingSelectionView: some View {
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

    private func ensureSelectedPerson() {
        if therapyDraft.selectedPerson == nil {
            therapyDraft.selectedPerson = persons.first
        }
    }

    private func goBack() {
        switch step {
        case .review:
            dismiss()
        case .recurrenceDuration:
            step = .review
        case .schedule:
            step = .recurrenceDuration
        case .person:
            step = .schedule
        case .stock:
            step = .person
        }
    }

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

    private var selectedDurationMode: DurationMode {
        if therapyDraft.useCount { return .count }
        if therapyDraft.courseEnabled { return .days }
        return .none
    }

    private var recurrenceSummaryText: String {
        switch therapyDraft.selectedFrequencyType {
        case .daily:
            if therapyDraft.interval == 1 { return "Ogni giorno" }
            return "Ogni \(therapyDraft.interval) giorni"
        case .specificDays:
            let dayNames = therapyDraft.byDay.map { dayName(for: $0) }
            return dayNames.isEmpty ? "In giorni specifici" : dayNames.joined(separator: ", ")
        case .cycle:
            return "\(therapyDraft.cycleOnDays) giorni di terapia, \(therapyDraft.cycleOffDays) giorni di pausa"
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
        default: return icsDay
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
            therapyDraft.selectedFrequencyType = .daily
            therapyDraft.interval = max(1, intervalDays)
        case .weekly(let weekDays):
            therapyDraft.selectedFrequencyType = .specificDays
            therapyDraft.byDay = weekDays
        case .cycle(let onDays, let offDays):
            therapyDraft.selectedFrequencyType = .cycle
            therapyDraft.interval = 1
            therapyDraft.byDay = []
            therapyDraft.cycleOnDays = onDays
            therapyDraft.cycleOffDays = offDays
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
        let summary = recurrenceSummaryText
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

    private func durationRow(_ mode: DurationMode) -> some View {
        Button {
            applyDurationMode(mode)
        } label: {
            HStack {
                Text(mode.label)
                Spacer()
                if selectedDurationMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private func applyDurationMode(_ mode: DurationMode) {
        switch mode {
        case .none:
            therapyDraft.courseEnabled = false
            therapyDraft.useUntil = false
            therapyDraft.useCount = false
        case .days:
            therapyDraft.courseEnabled = true
            therapyDraft.useCount = false
            syncCourseUntilFromCourse()
        case .count:
            therapyDraft.courseEnabled = false
            therapyDraft.useUntil = false
            therapyDraft.useCount = true
        }
    }

    private var daysSectionView: some View {
        let dayLabel = therapyDraft.courseTotalDays == 1 ? "giorno" : "giorni"
        return Section("Giorni") {
            Stepper(
                "Durata: \(therapyDraft.courseTotalDays) \(dayLabel)",
                value: $therapyDraft.courseTotalDays,
                in: 1...365
            )
            if let endDate = courseEndDate(from: startDateToday, totalDays: therapyDraft.courseTotalDays) {
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
        Section("Numero assunzioni") {
            Stepper("Numero assunzioni: \(therapyDraft.countNumber)", value: $therapyDraft.countNumber, in: 1...100)
            Text("Totale assunzioni pianificate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var doseUnitLabel: String {
        if let tipologia = selectedPackage?.tipologia.lowercased() {
            if tipologia.contains("capsul") { return "capsula" }
            if tipologia.contains("compress") { return "compressa" }
        }
        if let unit = selectedPackage?.dosageUnit.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
            return unit.lowercased()
        }
        return therapyDraft.doseUnit
    }

    private var defaultDoseAmount: Double {
        let amounts = therapyDraft.doses.map { $0.amount }
        guard let first = amounts.first else { return 1 }
        let isUniform = amounts.allSatisfy { abs($0 - first) < 0.0001 }
        return isUniform ? first : 1
    }

    private func doseDisplayText(amount: Double, unit: String) -> String {
        if amount == 0.5 {
            return "1/2 \(unit)"
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

    private var startDateToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func courseEndDate(from start: Date, totalDays: Int) -> Date? {
        let offset = max(0, totalDays - 1)
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        guard therapyDraft.selectedFrequencyType == .cycle,
              therapyDraft.cycleOnDays > 0,
              therapyDraft.cycleOffDays > 0 else {
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
        let onDays = therapyDraft.cycleOnDays
        let offDays = therapyDraft.cycleOffDays
        guard onDays > 0, offDays > 0 else { return true }
        let calendar = Calendar.current
        let daySOD = calendar.startOfDay(for: day)
        let diff = calendar.dateComponents([.day], from: startDay, to: daySOD).day ?? 0
        if diff < 0 { return false }
        let cycleLength = onDays + offDays
        guard cycleLength > 0 else { return true }
        let dayIndex = diff % cycleLength
        return dayIndex < onDays
    }

    private func syncCourseUntilFromCourse() {
        therapyDraft.useUntil = true
        therapyDraft.useCount = false
        if let endDate = courseEndDate(from: startDateToday, totalDays: therapyDraft.courseTotalDays) {
            therapyDraft.untilDate = endDate
        }
    }

    private func buildClinicalRules() -> ClinicalRules? {
        let course: CoursePlan? = (therapyDraft.courseEnabled && !therapyDraft.useCount)
            ? CoursePlan(totalDays: therapyDraft.courseTotalDays)
            : nil

        let taper: TaperPlan? = {
            guard therapyDraft.taperEnabled, !therapyDraft.taperSteps.isEmpty else { return nil }
            let steps = therapyDraft.taperSteps.map { draft in
                TaperStep(startDate: nil, durationDays: draft.durationDays, dosageLabel: draft.dosagePreset.label)
            }
            return steps.isEmpty ? nil : TaperPlan(steps: steps)
        }()

        let monitoring: [MonitoringAction]? = therapyDraft.monitoringEnabled
            ? [
                MonitoringAction(
                    kind: therapyDraft.monitoringKind,
                    requiredBeforeDose: true,
                    schedule: nil,
                    leadMinutes: therapyDraft.monitoringLeadMinutes
                )
            ]
            : nil

        let missedDosePolicy: MissedDosePolicy? = therapyDraft.missedDosePreset.policy

        let rules = ClinicalRules(
            safety: nil,
            course: course,
            taper: taper,
            interactions: nil,
            monitoring: monitoring,
            missedDosePolicy: missedDosePolicy
        )

        let hasAnyRule = course != nil || taper != nil || monitoring != nil || missedDosePolicy != nil
        return hasAnyRule ? rules : nil
    }

    private func resolvePerson() -> Person {
        if let selected = therapyDraft.selectedPerson { return selected }
        if let first = persons.first { return first }
        let newPerson = Person(context: context)
        newPerson.id = UUID()
        newPerson.nome = "Persona"
        newPerson.cognome = nil
        return newPerson
    }

    private func saveTherapyDraft(medicine: Medicine, package: Package, medicinePackage: MedicinePackage?) {
        if therapyDraft.courseEnabled && !therapyDraft.useCount {
            syncCourseUntilFromCourse()
        }

        let effectivePerson = resolvePerson()
        let clinicalRules = buildClinicalRules()
        let freq = therapyDraft.selectedFrequencyType == .specificDays ? "WEEKLY" : "DAILY"
        let byDay = therapyDraft.selectedFrequencyType == .specificDays ? therapyDraft.byDay : []
        let cycleOn = therapyDraft.selectedFrequencyType == .cycle ? therapyDraft.cycleOnDays : nil
        let cycleOff = therapyDraft.selectedFrequencyType == .cycle ? therapyDraft.cycleOffDays : nil

        therapyFormViewModel.saveTherapy(
            medicine: medicine,
            freq: freq,
            interval: max(1, therapyDraft.interval),
            until: therapyDraft.useUntil ? therapyDraft.untilDate : nil,
            count: therapyDraft.useCount ? therapyDraft.countNumber : nil,
            byDay: byDay,
            cycleOnDays: cycleOn,
            cycleOffDays: cycleOff,
            startDate: startDateToday,
            doses: therapyDraft.doses,
            package: package,
            medicinePackage: medicinePackage,
            importance: "standard",
            person: effectivePerson,
            manualIntake: options.first?.manual_intake_registration ?? false,
            clinicalRules: clinicalRules
        )
    }

    private func finishWizard() {
        guard let item = selectedItem, let pkg = selectedPackage ?? item.packages.first else {
            return
        }

        let medicine = Medicine(context: context)
        medicine.id = UUID()
        medicine.source_id = medicine.id
        medicine.visibility = "local"
        medicine.nome = item.name
        medicine.principio_attivo = item.principle
        medicine.obbligo_ricetta = item.requiresPrescription || pkg.requiresPrescription
        medicine.in_cabinet = true

        let package = Package(context: context)
        package.id = UUID()
        package.source_id = package.id
        package.visibility = "local"
        package.tipologia = pkg.tipologia
        package.unita = pkg.dosageUnit
        package.volume = pkg.volume
        package.valore = pkg.dosageValue
        package.numero = Int32(max(1, pkg.units))
        package.medicine = medicine
        medicine.addToPackages(package)

        let entry = MedicinePackage(context: context)
        entry.id = UUID()
        entry.created_at = Date()
        entry.source_id = entry.id
        entry.visibility = "local"
        entry.medicine = medicine
        entry.package = package
        entry.cabinet = nil
        medicine.addToMedicinePackages(entry)

        applyDeadlineInputs(to: medicine)
        saveTherapyDraft(medicine: medicine, package: package, medicinePackage: entry)

        stockService.addPurchase(medicine: medicine, package: package)
        stockService.setStockUnits(medicine: medicine, package: package, targetUnits: stockUnits)

        onFinish?()
        dismiss()
    }

    private var deadlineSummaryText: String {
        let monthText = deadlineMonthInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearText = deadlineYearInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let month = Int(monthText),
              let year = Int(yearText),
              (1...12).contains(month),
              (2000...2100).contains(year) else {
            return "Non impostata"
        }
        return String(format: "%02d/%04d", month, year)
    }

    private func sanitizeMonthInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return String(digits.prefix(2))
    }

    private func sanitizeYearInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return String(digits.prefix(4))
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
        stockUnits = max(1, pkg.units)
        step = .review
        didApplyPrefill = true
    }

    private var wizardTitle: String {
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
