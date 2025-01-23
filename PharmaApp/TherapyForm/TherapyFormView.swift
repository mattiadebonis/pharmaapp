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
    
    // MARK: - Modello
    var medicine: Medicine
    var package: Package
    
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
    
    // Sezione Orari: con pulsante + per aggiungere e - per rimuovere
    @State private var times: [Date] = [Date()]
    
    // Per aprire la schermata di selezione frequenza come sheet
    @State private var isShowingFrequencySheet = false
    
    // MARK: - Init
    init(
        medicine: Medicine,
        package: Package,
        context: NSManagedObjectContext
    ) {
        self.medicine = medicine
        self.package = package
        _therapyFormViewModel = StateObject(
            wrappedValue: TherapyFormViewModel(context: context)
        )
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    // Sezione Frequenza
                    Section {
                        Button {
                            isShowingFrequencySheet = true
                        } label: {
                            // Mostra la frequenza selezionata (giornaliera o in giorni specifici)
                            HStack {
                                Text("Frequenza")
                                Spacer()
                                Text(frequencyDescription())
                                    .foregroundColor(.blue)
                            }
                        }
                    } header: {
                        Text("Frequenza")
                    } footer: {
                        Text("Se programmi un orario, Salute ti invierà una notifica per ricordarti di assumere i farmaci.")
                    }
                    
                    // Sezione Orari
                    Section("Orari") {
                        ForEach(times.indices, id: \.self) { index in
                            HStack {
                                DatePicker("",
                                           selection: $times[index],
                                           displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                Text("1 compressa") // o personalizza dose
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                // Bottone per rimuovere l’orario
                                Button {
                                    // Elimina l’orario dall’array
                                    times.remove(at: index)
                                } label: {
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
                
                Button(action: {
                    saveTherapy()
                }) {
                    Text("Avanti")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle("\(medicine.nome) - \(package.tipologia) \(package.valore) \(package.unita) \(package.volume)")
            .onAppear {
                populateIfExisting()
            }
            // Sheet per la selezione della frequenza
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
        }
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
}

// MARK: - Salvataggio e Caricamento

extension TherapyFormView {
    
    private func saveTherapy() {
        switch selectedFrequencyType {
            case .daily:
                therapyFormViewModel.saveTherapy(
                    medicine: medicine,
                    freq: "DAILY",
                    interval: interval,
                    until: useUntil ? untilDate : nil,
                    count: useCount ? countNumber : nil,
                    byDay: [],
                    startDate: startDate,
                    times: times,
                    package: package         
                )
                
            case .specificDays:
                therapyFormViewModel.saveTherapy(
                    medicine: medicine,
                    freq: "WEEKLY",
                    interval: interval,              
                    until: useUntil ? untilDate : nil,
                    count: useCount ? countNumber : nil,
                    byDay: byDay,
                    startDate: startDate,
                    times: times,
                    package: package
                )
            }
        
        appViewModel.isSearchIndexPresented = false
        dismiss()
        
        // Debug
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
