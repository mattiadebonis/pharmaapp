import SwiftUI
import CoreData

struct MedicineWizardView: View {
    enum Step: Int, CaseIterable {
        case recurrenceDuration
        case schedule
        case person
        case stock

        var label: String {
            switch self {
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

        var useUntil: Bool = false
        var untilDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 30)
        var useCount: Bool = false
        var countNumber: Int = 1

        var doseAmount: Double = 1
        var doseUnit: String = "compressa"
        var times: [Date] = [Date()]

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

    @StateObject private var stockViewModel = MedicineFormViewModel(
        context: PersistenceController.shared.container.viewContext
    )
    @StateObject private var therapyFormViewModel = TherapyFormViewModel(
        context: PersistenceController.shared.container.viewContext
    )

    private let prefill: CatalogSelection?
    private let onFinish: (() -> Void)?
    @State private var didApplyPrefill = false
    @State private var step: Step = .recurrenceDuration
    @State private var selectedItem: CatalogItem?
    @State private var selectedPackage: CatalogPackage?
    @State private var therapyDraft = TherapyDraft()
    @State private var stockUnits: Int = 0
    @State private var wizardDetent: PresentationDetent = .medium
    @State private var deadlineMonthInput: String = ""
    @State private var deadlineYearInput: String = ""
    @State private var showTaperEditor = false

    private let allDaysICS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

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

    private var recurrenceDurationStep: some View {
        Form {
            Section(header: Text("Ripetizione")) {
                frequencyRow(.daily)
                frequencyRow(.specificDays)
            }

            if therapyDraft.selectedFrequencyType == .daily {
                dailySectionView
            }

            if therapyDraft.selectedFrequencyType == .specificDays {
                specificDaysSectionView
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
                ForEach(therapyDraft.times.indices, id: \.self) { index in
                    HStack {
                        DatePicker("", selection: $therapyDraft.times[index], displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text(doseDisplayText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            therapyDraft.times.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                Button {
                    therapyDraft.times.append(Date())
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
        case .recurrenceDuration:
            dismiss()
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

    private func frequencyRow(_ option: FrequencyType) -> some View {
        Button {
            therapyDraft.selectedFrequencyType = option
        } label: {
            HStack {
                Text(option.label)
                Spacer()
                if therapyDraft.selectedFrequencyType == option {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private var dailySectionView: some View {
        Section("Scegli intervallo") {
            Picker("Ogni", selection: $therapyDraft.interval) {
                ForEach(1..<31) { value in
                    Text("\(value) \(value == 1 ? "giorno" : "giorni")")
                        .tag(value)
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
                        let isSelected = therapyDraft.byDay.contains(day)
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

    private func toggleDay(_ day: String) {
        if let idx = therapyDraft.byDay.firstIndex(of: day) {
            therapyDraft.byDay.remove(at: idx)
        } else {
            therapyDraft.byDay.append(day)
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

    private var doseDisplayText: String {
        let unit = therapyDraft.doseUnit
        if therapyDraft.doseAmount == 0.5 {
            return "1/2 \(unit)"
        }
        let isInt = abs(therapyDraft.doseAmount.rounded() - therapyDraft.doseAmount) < 0.0001
        let numberString: String = {
            if isInt { return String(Int(therapyDraft.doseAmount.rounded())) }
            return String(therapyDraft.doseAmount).replacingOccurrences(of: ".", with: ",")
        }()
        let unitString: String = {
            guard therapyDraft.doseAmount > 1 else { return unit }
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
        return Calendar.current.date(byAdding: .day, value: offset, to: start)
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

    private func saveTherapyDraft(medicine: Medicine, package: Package) {
        if therapyDraft.courseEnabled && !therapyDraft.useCount {
            syncCourseUntilFromCourse()
        }

        let effectivePerson = resolvePerson()
        let clinicalRules = buildClinicalRules()
        let freq = therapyDraft.selectedFrequencyType == .daily ? "DAILY" : "WEEKLY"
        let byDay = therapyDraft.selectedFrequencyType == .specificDays ? therapyDraft.byDay : []

        therapyFormViewModel.saveTherapy(
            medicine: medicine,
            freq: freq,
            interval: max(1, therapyDraft.interval),
            until: therapyDraft.useUntil ? therapyDraft.untilDate : nil,
            count: therapyDraft.useCount ? therapyDraft.countNumber : nil,
            byDay: byDay,
            startDate: startDateToday,
            times: therapyDraft.times,
            package: package,
            importance: "standard",
            person: effectivePerson,
            manualIntake: medicine.manual_intake_registration,
            clinicalRules: clinicalRules
        )
    }

    private func finishWizard() {
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

        applyDeadlineInputs(to: medicine)
        saveTherapyDraft(medicine: medicine, package: package)

        stockViewModel.addPurchase(for: medicine, for: package)
        stockViewModel.setStockUnits(medicine: medicine, package: package, targetUnits: stockUnits)

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
        step = .recurrenceDuration
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
