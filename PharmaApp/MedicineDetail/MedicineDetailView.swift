import SwiftUI
import CoreData

struct MedicineDetailView: View {
    
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @EnvironmentObject var appViewModel: AppViewModel
    
    @StateObject private var viewModel = MedicineFormViewModel(
        context: PersistenceController.shared.container.viewContext
    )
    
    let medicine: Medicine
    let package: Package
    
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest private var therapies: FetchedResults<Therapy>
    
    @State private var showTherapySheet = false
    @State private var showPrescriptionSheet = false
    @State private var selectedTherapy: Therapy? = nil
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    // MARK: - Computed
    private var currentOption: Option? {
        options.first
    }
    
    private var prescriptionStatus: String {
        guard let option = currentOption, medicine.obbligo_ricetta else { return "" }
        let inEsaurimento = medicine.isInEsaurimento(option: option, recurrenceManager: recurrenceManager)
        if inEsaurimento {
            if medicine.hasPendingNewPrescription() {
                return "Da comprare"
            } else if medicine.hasNewPrescritpionRequest() {
                return "Ricetta richiesta"
            } else {
                return "Ricetta da chiedere"
            }
        }
        return ""
    }
    
    private var totalLeftover: Int {
        guard let therapies = medicine.therapies else { return 0 }
        return Int(therapies.reduce(0) { total, therapy in
            total + therapy.leftover()
        })
    }
    
    // Aggiungi la funzione helper per formattare la data
    private func formattedAssumptionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            if hour == 0 && minute == 0 {
                return "oggi"
            } else {
                let timeFormatter = DateFormatter()
                timeFormatter.dateStyle = .none
                timeFormatter.timeStyle = .short
                return timeFormatter.string(from: date)
            }
        } else if calendar.isDateInTomorrow(date) {
            return "Domani"
        } else if let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: Date()),
                  calendar.isDate(date, inSameDayAs: dayAfterTomorrow) {
            return "Dopodomani"
        }
        let defaultFormatter = DateFormatter()
        defaultFormatter.dateStyle = .short
        defaultFormatter.timeStyle = .short
        return defaultFormatter.string(from: date)
    }
    
    init(medicine: Medicine, package: Package) {
        self.medicine = medicine
        self.package = package
        _therapies = FetchRequest(
            entity: Therapy.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Therapy.start_date, ascending: true)],
            predicate: NSPredicate(format: "medicine == %@", medicine)
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Dettagli")) {
                    HStack { Text("Nome"); Spacer(); Text("\(medicine.nome ?? "") - \(package.volume)") }
                    HStack { Text("Scorte rimanenti"); Spacer(); Text("\(totalLeftover)").foregroundColor(.green) }
                }
                Section(header: Text("Terapie")) {
                    if !therapies.isEmpty {
                        ForEach(therapies, id: \.objectID) { therapy in
                            Button { 
                                selectedTherapy = therapy; 
                                showTherapySheet = true 
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        let rule = recurrenceManager.parseRecurrenceString(
                                        therapy.rrule ?? "")
                                        Text("\(recurrenceManager.describeRecurrence(rule: rule))")
                                            
                                        Text(formattedAssumptionDate(
                                            recurrenceManager.nextOccurrence(
                                                rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
                                                startDate: therapy.start_date ?? Date(),
                                                after: Date(),
                                                doses: therapy.doses as NSSet?
                                            ) ?? (therapy.start_date ?? Date())
                                        ))
                                        Spacer()
                                        let person = therapy.person
                                        if let name = person.nome {
                                            Text("\(name) \(person.cognome ?? "")")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    
                                }
                            }
                            .accessibilityLabel("Visualizza dettagli terapia")
                        }
                    }
                    Button { 
                        selectedTherapy = nil; 
                        showTherapySheet = true 
                    } label: {
                        Label("Programma una nuova terapia", systemImage: "plus.circle")
                    }
                    .accessibilityLabel("Programma nuova terapia")
                }
                Section(header: Text("Azioni")) {
                    if medicine.obbligo_ricetta {
                        Button { showPrescriptionSheet.toggle() } label: {
                            Label("Richiedi ricetta", systemImage: "doc.text")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Richiedi ricetta")
                    }
                    Button { viewModel.saveForniture(medicine: medicine, package: package) } label: {
                        Label("Acquistato", systemImage: "cart")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Segna come acquistato")
                }
            }
            .navigationTitle(medicine.nome ?? "Dettaglio")
        }
        .presentationDetents([.medium, .large])
        
        // Sheet per gestione Terapie
        .sheet(isPresented: $showTherapySheet) {
            TherapyFormView(
                medicine: medicine,
                package: package,
                context: context,
                editingTherapy: selectedTherapy
            )
            .id(selectedTherapy?.id ?? UUID())
            .presentationDetents([.medium, .large])
        }
        
        // Sheet per gestione Ricetta
        .sheet(isPresented: $showPrescriptionSheet) {
            PrescriptionManagementView(
                medicine: medicine,
                package: package
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    // NEW: Helper to convert a RecurrenceRule to natural language
    private func naturalLanguageDescription(for rule: RecurrenceRule) -> String {
        var desc = ""
        if rule.freq.uppercased() == "DAILY" {
            desc = rule.interval > 1 ? "Ogni \(rule.interval) giorni" : "Ogni giorno"
        } else if rule.freq.uppercased() == "WEEKLY" {
            desc = rule.interval > 1 ? "Ogni \(rule.interval) settimane" : "Ogni settimana"
            if !rule.byDay.isEmpty {
                let days = rule.byDay.map { dayName(for: $0) }.joined(separator: ", ")
                desc += " (\(days))"
            }
        } else {
            desc = "Ricorrente"
        }
        if let until = rule.until {
            let df = DateFormatter()
            df.dateStyle = .medium
            desc += " fino al \(df.string(from: until))"
        }
        if let count = rule.count {
            desc += ", \(count) volte"
        }
        return desc
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
    
    private func nextDoseDescription(for medicine: Medicine) -> String {
        guard let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty else {
            return "Nessuna terapia in corso"
        }
        
        let now = Date()
        var nextDates: [Date] = []
        
        for therapy in therapies {
            guard let rruleString = therapy.rrule, !rruleString.isEmpty else { continue }
            let rule = recurrenceManager.parseRecurrenceString(rruleString)
            if let nextOccurrence = recurrenceManager.nextOccurrence(
                rule: rule,
                startDate: therapy.start_date ?? now,
                after: now,
                doses: therapy.doses as NSSet?
            ) {
                nextDates.append(nextOccurrence)
            }
        }
        
        guard let nearestDate = nextDates.sorted().first else {
            return "Nessun promemoria impostato"
        }
        
        return dateFormatter.string(from: nearestDate)
    }
}
