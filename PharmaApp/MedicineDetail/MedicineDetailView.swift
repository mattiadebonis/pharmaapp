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
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                Text("\(medicine.nome ?? "") - \(package.volume)")
                    .font(.title2)
                    .bold()
                    .padding(.top)
                Text("Scorte rimanenti: \(totalLeftover)")
                    .font(.headline)
                    .foregroundColor(.green)
                // Sezione Terapie: aggiornata per mostrare le terapie come in TherapiesIndex
                Text("Terapie")
                    .font(.headline)
                if let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty {
                    ForEach(therapies.sorted { ($0.start_date ?? Date()) < ($1.start_date ?? Date()) }, id: \.objectID) { therapy in
                        Button {
                            selectedTherapy = therapy
                            showTherapySheet = true
                        } label: {
                            HStack {
                                if let startDate = therapy.start_date,
                                   let rrule = therapy.rrule,
                                   let nextDate = recurrenceManager.nextOccurrence(
                                        rule: recurrenceManager.parseRecurrenceString(rrule),
                                        startDate: startDate,
                                        after: Date(),
                                        doses: therapy.doses as NSSet?) {
                                    Text("\(formattedAssumptionDate(nextDate))")
                                } else if let startDate = therapy.start_date {
                                    Text("\(formattedAssumptionDate(startDate))")
                                }
                                if let nome = therapy.person.nome,
                                   let cognome = therapy.person.cognome,
                                   !(nome.isEmpty && cognome.isEmpty) {
                                    HStack {
                                        Image(systemName: "person")
                                        Text("\(nome) \(cognome)")
                                    }
                                    .foregroundColor(.secondary)
                                }
                                Spacer()


                                /* if let option = currentOption, option.manual_intake_registration {
                                    Button(action: {
                                        viewModel.addIntake(for: medicine, for: package, for: therapy)
                                    }) {
                                        HStack{
                                            Image(systemName: "pills")
                                            Text("Assunto")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .bold()
                                    
                                } */
                            }
                        }
                        Divider()
                    }
                } 
                 
                Button {
                 
                    selectedTherapy = nil
                    showTherapySheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Programma una nuova terapia")
                    }
                    
                }
                 
                VStack(spacing: 10){
                    // Bottone gestione ricetta
                    if medicine.obbligo_ricetta {
                        Button(action: {
                            showPrescriptionSheet.toggle()
                        }) {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("Richiedi ricetta")
                                
                            }.frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.borderedProminent)
                        .bold()
                    }
                    
                    // Pulsante Acquisto
                    Button(action: {
                        viewModel.saveForniture(medicine: medicine, package: package)
                    }) {
                        HStack{
                            Image(systemName: "cart")
                            Text("Acquistato")
                        }.frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .bold()

                    
                }
                
                
                
            }
            .padding(.horizontal)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
