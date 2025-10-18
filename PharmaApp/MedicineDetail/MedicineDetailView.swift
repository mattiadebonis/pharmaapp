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
    
    // UI: espansioni per una schermata iniziale pulita
    @State private var expandTherapies = false
    @State private var expandParamName = false
    @State private var expandParamPrincipio = false
    @State private var expandParamObbligo = false
    @State private var expandParamPackage = false
    
    // Campi di editing
    @State private var editedName: String = ""
    @State private var editedPrincipio: String = ""
    @State private var editedObbligo: Bool = false
    @State private var editedNumero: String = ""
    @State private var editedTipologia: String = ""
    @State private var editedValore: String = ""
    @State private var editedUnita: String = ""
    @State private var editedVolume: String = ""
    
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
        if let therapies = medicine.therapies, !therapies.isEmpty {
            return therapies.reduce(0) { total, therapy in
                total + Int(therapy.leftover())
            }
        }
        return medicine.remainingUnitsWithoutTherapy() ?? 0
    }
    
    private var leftoverColor: Color {
        totalLeftover <= 0 ? .red : .green
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
        _editedName = State(initialValue: medicine.nome)
        _editedPrincipio = State(initialValue: medicine.principio_attivo)
        _editedObbligo = State(initialValue: medicine.obbligo_ricetta)
        _editedNumero = State(initialValue: String(package.numero))
        _editedTipologia = State(initialValue: package.tipologia)
        _editedValore = State(initialValue: String(package.valore))
        _editedUnita = State(initialValue: package.unita)
        _editedVolume = State(initialValue: package.volume)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Schermata iniziale pulita: riepilogo minimo
                Section {
                    HStack { Text("Nome"); Spacer(); Text(medicine.nome).foregroundStyle(.primary) }
                    HStack { Text("Scorte rimanenti"); Spacer(); Text("\(totalLeftover)").foregroundColor(leftoverColor) }
                }

                // Sezioni espandibili per terapie e parametri
                Section {
                    DisclosureGroup(isExpanded: $expandTherapies) {
                        if !therapies.isEmpty {
                            ForEach(therapies, id: \.objectID) { therapy in
                                Button {
                                    selectedTherapy = therapy
                                    showTherapySheet = true
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            let rruleString = therapy.rrule ?? ""
                                            let rule = recurrenceManager.parseRecurrenceString(rruleString)
                                            let hasDoses = (therapy.doses as? Set<Dose>)?.isEmpty == false
                                            if hasDoses && !rruleString.isEmpty {
                                                Text("\(recurrenceManager.describeRecurrence(rule: rule))")
                                            } else {
                                                Text("Nessuna pianificazione").foregroundColor(.secondary)
                                            }
                                            if hasDoses, let next = recurrenceManager.nextOccurrence(
                                                rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
                                                startDate: therapy.start_date ?? Date(),
                                                after: Date(),
                                                doses: therapy.doses as NSSet?
                                            ) { Text(formattedAssumptionDate(next)) }
                                            Spacer()
                                            let person = therapy.person
                                            if let name = person.nome { Text("\(name) \(person.cognome ?? "")").foregroundColor(.secondary) }
                                        }
                                    }
                                }
                                .accessibilityLabel("Visualizza dettagli terapia")
                            }
                        }
                        Button { selectedTherapy = nil; showTherapySheet = true } label: { Label("Programma una nuova terapia", systemImage: "plus.circle") }
                    } label: { Label("Terapie", systemImage: "calendar") }

                    DisclosureGroup(isExpanded: $expandParamName) {
                        TextField("Nome", text: $editedName)
                        HStack { Spacer(); Button("Salva") { saveName() } }
                    } label: { Label("Nome medicinale", systemImage: "textformat") }

                    DisclosureGroup(isExpanded: $expandParamPrincipio) {
                        TextField("Principio attivo", text: $editedPrincipio)
                        HStack { Spacer(); Button("Salva") { savePrincipio() } }
                    } label: { Label("Principio attivo", systemImage: "leaf") }

                    DisclosureGroup(isExpanded: $expandParamObbligo) {
                        Toggle("Obbligo di ricetta", isOn: $editedObbligo)
                        HStack { Spacer(); Button("Salva") { saveObbligo() } }
                    } label: { Label("Obbligo ricetta", systemImage: "doc.text") }

                    DisclosureGroup(isExpanded: $expandParamPackage) {
                        TextField("Unità per confezione", text: $editedNumero).keyboardType(.numberPad)
                        TextField("Tipologia", text: $editedTipologia)
                        TextField("Valore", text: $editedValore).keyboardType(.numberPad)
                        TextField("Unità", text: $editedUnita)
                        TextField("Volume", text: $editedVolume)
                        HStack { Spacer(); Button("Salva") { savePackage() } }
                    } label: { Label("Confezione", systemImage: "cube.box") }
                }

                // Azioni snelle
                Section {
                    if medicine.obbligo_ricetta {
                        Button { showPrescriptionSheet.toggle() } label: { Label("Richiedi ricetta", systemImage: "doc.text") }
                    }
                    Button { viewModel.saveForniture(medicine: medicine, package: package) } label: { Label("Acquistato", systemImage: "cart") }
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

// MARK: - Salvataggi parametri
private extension MedicineDetailView {
    func saveName() {
        medicine.nome = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
    }
    func savePrincipio() {
        medicine.principio_attivo = editedPrincipio
        try? context.save()
    }
    func saveObbligo() {
        medicine.obbligo_ricetta = editedObbligo
        try? context.save()
    }
    func savePackage() {
        if let n = Int32(editedNumero) { package.numero = n }
        if let v = Int32(editedValore) { package.valore = v }
        package.tipologia = editedTipologia
        package.unita = editedUnita
        package.volume = editedVolume
        try? context.save()
    }
}
