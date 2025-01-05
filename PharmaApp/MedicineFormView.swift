//
//  MedicineFormView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import SwiftUI
import CoreData

struct MedicineFormView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appViewModel: AppViewModel

    @StateObject var medicineFormViewModel: MedicineFormViewModel
    var medicine: Medicine
   
    // MARK: - UI
    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    let pastelGreen = Color(red: 179/255, green: 207/255, blue: 190/255, opacity: 1.0)
    let textColor = Color(red: 47/255, green: 47/255, blue: 47/255, opacity: 1.0)
    let pastelPink = Color(red: 248/255, green: 200/255, blue: 220/255, opacity: 1.0)

    @State private var selectedPackage: Package?

    @State private var startDate: Date = Date()
    @State private var repeatDate: Bool = false
    
    // Parametri ricorrenza
    @State private var freq: String = "WEEKLY"
    @State private var interval: Int = 1
    @State private var useUntil: Bool = false
    @State private var untilDate: Date = Date().addingTimeInterval(60*60*24*30)
    @State private var useCount: Bool = false
    @State private var countNumber: Int = 1
    
    // Per i giorni della settimana in ICS
    // (se vuoi farlo in italiano, vedi conversione sotto)
    let allDaysICS = ["MO","TU","WE","TH","FR","SA","SU"]
    @State private var byDay: [String] = ["MO"]  // selezione iniziale
    
    // Frequenze disponibili
    let freqOptions: [(label: String, value: String)] = [
        ("Giornaliera", "DAILY"),
        ("Settimanale", "WEEKLY"),
        ("Mensile",    "MONTHLY"),
        ("Annuale",    "YEARLY")
    ]

    init(
        medicine: Medicine, 
        context: NSManagedObjectContext
    ) {
        self.medicine = medicine
        _medicineFormViewModel = StateObject(wrappedValue: MedicineFormViewModel(context: context))
    }
    
    var body: some View  {
        NavigationView {
            Form {
                Section("Ultimo acquisto"){
                    Button("Aggiungi scorte") {
                        medicineFormViewModel.saveForniture(medicine: medicine)
                        dismiss()
                        appViewModel.isSearchIndexPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Section("Dosaggio") {
                    let packagesArray = Array(medicine.packages ?? [])
                    ForEach(packagesArray, id: \.id) { package in
                        Button {
                            selectedPackage = package
                        } label: {
                            HStack {
                                Text("\(package.tipologia) - \(package.valore) \(package.unita) - \(package.volume)")
                                Spacer()
                                if selectedPackage?.id == package.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
                
                Section("Tempo assunzione") {
                   
                    DatePicker("Data inizio:", selection: $startDate, displayedComponents: .date)
                    Toggle("Ripeti", isOn: $repeatDate)
                }
                
                // Se l’utente abilita la ripetizione, mostriamo le impostazioni
                if repeatDate {
                    Section("Ricorrenza") {
                        Picker("Ripeti:", selection: $freq) {
                            ForEach(freqOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        HStack {
                            Text("Ogni \(interval) \(freqLabel(freq))")
                            Spacer()
                            Stepper("", value: $interval, in: 1...30)
                                .labelsHidden()
                        }
                    }
                    
                    // Se freq = WEEEKLY, selezione giorni della settimana
                    if freq == "WEEKLY" {
                        Section("Giorni della settimana") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(allDaysICS, id: \.self) { day in
                                        DayTogglePill(
                                            day: day,
                                            isSelected: byDay.contains(day),
                                            onToggle: {
                                                toggleDay(day)
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    
                    // Esempio per freq = MONTHLY
                    if freq == "MONTHLY" {
                        Section("Giorni del mese") {
                            Text("Seleziona i giorni del mese (es. 1, 15, 31) se serve...")
                            // ... la logica la decidi tu
                        }
                    }
                    
                    Section("Fine ripetizione") {
                        Toggle("Termina il", isOn: $useUntil)
                        if useUntil {
                            DatePicker("Data di fine", selection: $untilDate, displayedComponents: .date)
                        }
                        Toggle("Numero ripetizioni massime", isOn: $useCount)
                        if useCount {
                            Stepper(
                                "Numero ripetizioni: \(countNumber)",
                                value: $countNumber,
                                in: 1...100
                            )
                        }
                    }
                }
                Section {
                    Button("Salva") {

                        let effectiveFreq = repeatDate ? freq : nil
                        let effectiveInterval = repeatDate ? interval : 1
                        let effectiveUntil = (repeatDate && useUntil) ? untilDate : nil
                        let effectiveCount = (repeatDate && useCount) ? countNumber : nil
                        let effectiveByDay = repeatDate ? byDay : []
                        
                        medicineFormViewModel.saveTherapy(
                            medicine: medicine,
                            freq: effectiveFreq,
                            interval: effectiveInterval,
                            until: effectiveUntil,
                            count: effectiveCount,
                            byDay: effectiveByDay,
                            startDate: startDate
                        )
                        
                        appViewModel.isSearchIndexPresented = false
                        dismiss()
                        
                        if let success = medicineFormViewModel.successMessage {
                            print("Success: \(success)")
                        }
                        if let error = medicineFormViewModel.errorMessage {
                            print("Error: \(error)")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .onAppear {
                        populateIfExisting()
                    }
                    
                }
            }
            .navigationTitle(medicine.nome)
            
        }
    }

    private func populateIfExisting() {
        if let existingTherapy = medicine.therapies?.first {
            populateFromTherapy(existingTherapy)
            return
        }
        
        guard let fetchedTherapy = medicineFormViewModel.fetchTherapy(for: medicine) else { return }
        populateFromTherapy(fetchedTherapy)
    }

    private func populateFromTherapy(_ therapy: Therapy) {
        // Se c'è una rrule, facciamo il parse
        if let rruleString = therapy.rrule, !rruleString.isEmpty {
            let parsedRule = RecurrenceManager(context: context)
                .parseRecurrenceString(rruleString)

            self.freq = parsedRule.freq
            self.interval = parsedRule.interval
            
            if let until = parsedRule.until {
                self.useUntil = true
                self.untilDate = until
            } else {
                self.useUntil = false
            }
            
            if let count = parsedRule.count {
                self.useCount = true
                self.countNumber = count
            } else {
                self.useCount = false
            }
            
            self.byDay = parsedRule.byDay
            self.repeatDate = true
        }
        
        // Se esiste la start_date, la recuperiamo
        if let existingStartDate = therapy.value(forKey: "start_date") as? Date {
            self.startDate = existingStartDate
        }
    }

    func freqLabel(_ freq: String) -> String {
        switch freq {
        case "DAILY":   return interval == 1 ? "giorno"     : "giorni"
        case "WEEKLY":  return interval == 1 ? "settimana"  : "settimane"
        case "MONTHLY": return interval == 1 ? "mese"       : "mesi"
        case "YEARLY":  return interval == 1 ? "anno"       : "anni"
        default:        return "volte"
        }
    }
    
    /// Aggiunge o rimuove il giorno dalla lista byDay
    func toggleDay(_ day: String) {
        if let idx = byDay.firstIndex(of: day) {
            byDay.remove(at: idx)
        } else {
            byDay.append(day)
        }
    }

    
}


struct DayTogglePill: View {
    let day: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            Text(day)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundColor(isSelected ? .white : .blue)
                .background(isSelected ? Color.blue : Color.clear)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue, lineWidth: 1)
                )
        }
        .animation(.easeInOut, value: isSelected)
    }
}
