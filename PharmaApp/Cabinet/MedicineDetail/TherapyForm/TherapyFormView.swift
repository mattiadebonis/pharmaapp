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
    
    // Aggiunta per supportare la modifica: se valorizzata, la vista si popola con questa terapia
    var editingTherapy: Therapy?
    
    // MARK: - ViewModel
    @StateObject var therapyFormViewModel: TherapyFormViewModel
    
    // MARK: - Stato Frequenza
    @State private var selectedFrequencyType: FrequencyType = .daily
    
    /// Se l’utente sceglie giornaliera, freq = "DAILY".
    /// Se sceglie giorni specifici, freq = "WEEKLY" con byDay personalizzati.
    @State private var freq: String = "DAILY"
    
    // byDay è utile solo per “in giorni specifici”
    @State private var byDay: [String] = ["MO"]  // Lunedì di default
    
    // Se vuoi mantenere la possibilità di interrompere la terapia in una data,
    // tieni useUntil e useCount. Altrimenti puoi rimuoverli se non servono.
    @State private var useUntil: Bool = false
    @State private var untilDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 30)
    @State private var useCount: Bool = false
    @State private var countNumber: Int = 1
    @State private var interval: Int = 1
    // Data di inizio
    @State private var startDate: Date = Date()
    @State private var manualIntakeRegistration: Bool = true
    @State private var therapyDescriptionText: String = ""
    @State private var doseAmount: Double = 1
    @State private var doseUnit: String = "compressa"
    
    // Sezione Orari: con pulsante + per aggiungere e - per rimuovere
        @State private var times: [Date] = [Date()]
    @State private var isShowingFrequencySheet = false
    
    // MARK: - Init
    init(
        medicine: Medicine,
        package: Package,
        context: NSManagedObjectContext,
        editingTherapy: Therapy? = nil
    ) {
        self.medicine = medicine
        self.package = package
        self.editingTherapy = editingTherapy
        _therapyFormViewModel = StateObject(
            wrappedValue: TherapyFormViewModel(context: context)
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                therapyDescriptionSection
                Section(header: Text("Persona")) {
                    Picker("Seleziona Persona", selection: $selectedPerson) {
                        ForEach(persons, id: \.self) { person in
                            Text("\(person.nome ?? "") \(person.cognome ?? "")")
                                .tag(person as Person?)
                        }
                    }
                    .accessibilityIdentifier("PersonPicker")
                }
                
                // Sezione Frequenza
                Section(header: Text("Frequenza")) {
                    Button {
                        isShowingFrequencySheet = true
                    } label: {
                        HStack {
                            Text("Frequenza")
                            Spacer()
                            Text(frequencyDescription())
                                .foregroundColor(.blue)
                        }
                    }
                    .accessibilityLabel("Seleziona frequenza")
                }
                
                // Sezione Orari
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
                Section(header: Text("Promemoria")) {
                    Toggle(isOn: $manualIntakeRegistration) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chiedi conferma assunzione")
                            Text("Quando ricevi il promemoria, conferma manualmente l'assunzione.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
                        useUntil: $useUntil,
                        untilDate: $untilDate,
                        useCount: $useCount,
                        countNumber: $countNumber,
                        startDate: $startDate,
                        interval: $interval
                    ) {
                        isShowingFrequencySheet = false
                    }
                }
            }
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

    private var canSave: Bool {
        // Persona obbligatoria
        guard let _ = selectedPerson else { return false }
        // In edit sempre abilitato; in creazione abilitiamo comunque perché la logica di save evita duplicati aggiornando.
        return true
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(therapySummaryPills, id: \.self) { token in
                        Text(token)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var therapySummaryPills: [String] {
        var parts: [String] = []
        if let personName = selectedPersonName {
            parts.append("👤 \(personName)")
        }
        parts.append("💊 \(doseDisplayText)")
        parts.append("🔁 \(frequencySummaryText)")
        if let timesText = timesSummaryText {
            parts.append("⏰ \(timesText)")
        }
        parts.append(manualIntakeRegistration ? "✅ Conferma" : "Senza conferma")
        return parts
    }

    private var selectedPersonName: String? {
        guard let selectedPerson else { return nil }
        let first = (selectedPerson.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (selectedPerson.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let components = [first, last].filter { !$0.isEmpty }
        let full = components.joined(separator: " ")
        return full.isEmpty ? nil : full
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

    private var timesSummaryText: String? {
        guard !times.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return times
            .sorted()
            .map { formatter.string(from: $0) }
            .joined(separator: ", ")
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

        if let requiresConfirmation = parsed.requiresConfirmation {
            manualIntakeRegistration = requiresConfirmation
        }

        if let duration = parsed.duration {
            useUntil = true
            useCount = false
            let base = startDate
            let until: Date?
            switch duration.unit {
            case .days:
                until = Calendar.current.date(byAdding: .day, value: duration.value, to: base)
            case .weeks:
                until = Calendar.current.date(byAdding: .day, value: duration.value * 7, to: base)
            case .months:
                until = Calendar.current.date(byAdding: .month, value: duration.value, to: base)
            }
            if let until {
                untilDate = until
            }
        }
    }
}

// MARK: - Salvataggio e Caricamento

extension TherapyFormView {
    
    private func saveTherapy() {
        let effectiveImportance = editingTherapy?.importance ?? "standard"

        // Persona associata: in modifica usa quella della therapy; altrimenti usa selezione/first/crea
        let effectivePerson: Person = {
            if let t = editingTherapy { return t.person }
            if let sel = selectedPerson { return sel }
            if let first = persons.first { return first }
            let newPerson = Person(context: context)
            newPerson.id = UUID()
            newPerson.nome = ""
            newPerson.cognome = ""
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
                    startDate: startDate,
                    times: times,
                    package: package,
                    importance: effectiveImportance,
                    person: effectivePerson,
                    manualIntake: manualIntakeRegistration
                )
            } else {
                therapyFormViewModel.updateTherapy(
                    therapy: therapyToUpdate,
                    freq: "WEEKLY",
                    interval: interval,
                    until: useUntil ? untilDate : nil,
                    count: useCount ? countNumber : nil,
                    byDay: byDay,
                    startDate: startDate,
                    times: times,
                    package: package,
                    importance: effectiveImportance,
                    person: effectivePerson,
                    manualIntake: manualIntakeRegistration
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
                    startDate: startDate,
                    times: times,
                    package: package,
                    importance: "standard",
                    person: effectivePerson,
                    manualIntake: manualIntakeRegistration
                )
            } else {
                therapyFormViewModel.saveTherapy(
                    medicine: medicine,
                    freq: "WEEKLY",
                    interval: interval,
                    until: useUntil ? untilDate : nil,
                    count: useCount ? countNumber : nil,
                    byDay: byDay,
                    startDate: startDate,
                    times: times,
                    package: package,
                    importance: "standard",
                    person: effectivePerson,
                    manualIntake: manualIntakeRegistration
                )
            }
        }
        
        appViewModel.isSearchIndexPresented = false
        dismiss()
        
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
            
            if let until = parsedRule.until {
                useUntil = true
                untilDate = until
            } else {
                useUntil = false
            }
            if let count = parsedRule.count {
                useCount = true
                countNumber = count
            } else {
                useCount = false
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
        
        if let start = therapy.value(forKey: "start_date") as? Date {
            startDate = start
        }
        
        if let existingDoses = therapy.doses as? Set<Dose> {
            let sortedDoses = existingDoses.sorted { $0.time < $1.time }
            self.times = sortedDoses.map { $0.time }
        } else {
            self.times = []
        }
        self.manualIntakeRegistration = therapy.manual_intake_registration
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
    @Binding var useUntil: Bool
    @Binding var untilDate: Date
    @Binding var useCount: Bool
    @Binding var countNumber: Int
    @Binding var startDate: Date
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
            Section{
                DatePicker("Inizio", selection: $startDate, displayedComponents: .date)

                Toggle("Termina il", isOn: $useUntil)
                if useUntil {
                    DatePicker("Data di fine", selection: $untilDate, displayedComponents: .date)
                }
                
                Toggle("Numero ripetizioni massime", isOn: $useCount)
                if useCount {
                    Stepper("Numero ripetizioni: \(countNumber)",
                            value: $countNumber,
                            in: 1...100)
                }
            
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
