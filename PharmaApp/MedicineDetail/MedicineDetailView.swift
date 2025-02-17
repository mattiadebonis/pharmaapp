import SwiftUI
import CoreData

struct MedicineDetailView: View {
    
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @EnvironmentObject var appViewModel: AppViewModel
    
    // MARK: - ViewModel dedicato
    @StateObject private var viewModel = MedicineFormViewModel(
        context: PersistenceController.shared.container.viewContext
    )
    
    // MARK: - Dati passati
    let medicine: Medicine
    let package: Package
    
    // MARK: - Fetch delle opzioni
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    
    // MARK: - Stato per modali
    @State private var showTherapySheet = false
    @State private var showPrescriptionSheet = false
    
    // MARK: - Supporto per ricorrenza/prescrizione
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    
    // MARK: - DateFormatter
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
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Titolo
                Text("\(medicine.nome ?? "") - \(package.volume)")
                    .font(.title2)
                    .bold()
                    .padding(.top)
                
                Button(action: {
                    showTherapySheet.toggle()
                }) {
                    HStack {
                        Image(systemName: "calendar")
                        Text("Prossima dose: \(nextDoseDescription(for: medicine))")
                    }
                }
                Divider()

                // Quantità residua
                Text("Scorte rimanenti: \(totalLeftover)")
                    .font(.headline)
                    .foregroundColor(.green)
                
                Divider()
                ScrollView(.horizontal){
                    
                }
                Spacer()
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

                    // Pulsante Assunzione
                    if let option = currentOption, option.manual_intake_registration {
                        Button(action: {
                            viewModel.addIntake(for: medicine, for: package)
                        }) {
                            HStack{
                                Image(systemName: "pills")
                                Text("Assunto")
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .bold()
                        .font(.system(size: 18))
                    }
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
                context: context
            )
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
