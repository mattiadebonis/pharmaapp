//
//  MedicineDetailView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 23/01/25.
//

import SwiftUI
import CoreData

struct MedicineDetailView: View {
    
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    // Se stai usando un appViewModel globale
    @EnvironmentObject var appViewModel: AppViewModel
    
    // MARK: - ViewModel dedicato (ex MedicineFormViewModel)
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
    
    /// Esempio di status in base a logiche di ricetta e scorte
    private var prescriptionStatus: String? {
        guard let option = currentOption, medicine.obbligo_ricetta else { return nil }
        let inEsaurimento = medicine.isInEsaurimento(option: option, recurrenceManager: recurrenceManager)
        if inEsaurimento {
            if medicine.hasPendingNewPrescription() {
                return "Da comprare"
            } else if medicine.hasNewPrescritpionRequest() {
                return "Ricetta richiesta"
            } else {
                return "Ricetta da chiedere"
            }
        } else {
            return nil
        }
    }
    
    /// Calcolo scorte totali, se esiste la logica in `Therapy`
    private var totalLeftover: Int {
        guard let therapies = medicine.therapies else { return 0 }
        return Int(therapies.reduce(0) { total, therapy in
            total + therapy.leftover()
        })
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Titolo
                Text("Dettaglio Farmaco: \(medicine.nome ?? "")")
                    .font(.title3)
                    .bold()
                    .padding(.top)
                
                // Info base
                Text("Dosaggio: \(package.tipologia) \(package.valore) \(package.unita) \(package.volume)")
                    .foregroundColor(.gray)
                
                // Se il farmaco ha ricetta e c’è uno status da mostrare (es: "Ricetta richiesta")
                if let status = prescriptionStatus {
                    HStack {
                        Text(status)
                            .foregroundColor(.blue)
                    }
                }
                
                // Quantità residua
                Text("Scorte rimanenti: \(totalLeftover)")
                    .font(.headline)
                    .foregroundColor(.green)
                
                // Data ultima assunzione
                if let lastIntakeDate = fetchLastIntakeDate(for: medicine) {
                    Text("Ultima assunzione: \(dateFormatter.string(from: lastIntakeDate))")
                } else {
                    Text("Ultima assunzione: -")
                }
                
                // Prossima dose (se gestisci un calcolo interno)
                Text("Prossima dose: \(nextDoseDescription(for: medicine))")
                    .foregroundColor(.gray)
                
                Divider()
                
                // Se vuoi modificare le terapie (frequenza, orari...) apri la TherapyFormView
                Button(action: {
                    showTherapySheet.toggle()
                }) {
                    Label("Gestione Terapie", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                
                // MARK: - Azioni principali

                // 1) Registra Acquisto
                Button(action: {
                    viewModel.saveForniture(medicine: medicine, package: package)
                }) {
                    Label("Registra Acquisto", systemImage: "cart")
                }
                .buttonStyle(.borderedProminent)
                
                // 2) Registra Assunzione
                if let option = currentOption, option.manual_intake_registration {
                    Button(action: {
                        viewModel.addIntake(for: medicine, for: package)
                    }) {
                        Label("Registra Assunzione", systemImage: "pills")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // Se hai un flusso dedicato alla ricetta
                if medicine.obbligo_ricetta {
                    Button(action: {
                        showPrescriptionSheet.toggle()
                    }) {
                        Label("Gestione Ricetta", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large]) // Modale a metà schermo
        
        // MARK: - Sheet per la gestione Terapie (la tua TherapyFormView)
        .sheet(isPresented: $showTherapySheet) {
            TherapyFormView(
                medicine: medicine,
                package: package,
                context: context
            )
            .presentationDetents([.medium, .large])
        }
        
        // MARK: - Sheet per la gestione Ricetta
        .sheet(isPresented: $showPrescriptionSheet) {
            PrescriptionManagementView(
                medicine: medicine,
                package: package
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - Funzioni di utilità
    
    /// 1) Recupera la data di ultima assunzione (es. da tabella Log di tipo "intake")
    private func fetchLastIntakeDate(for medicine: Medicine) -> Date? {
        let fetchRequest: NSFetchRequest<Log> = NSFetchRequest(entityName: "Log")
        // Cerchiamo i Log di tipo "intake" associati a questo farmaco
        fetchRequest.predicate = NSPredicate(format: "medicine == %@ AND type == %@", medicine, "intake")
        // Ordine discendente per prendere il più recente
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = 1
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.first?.timestamp
        } catch {
            print("Errore nel fetch di lastIntakeDate: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 2) Descrizione della prossima dose, basandoci sulle Therapy e le `rrule`.
    /// Esempio di integrazione con `RecurrenceManager`: cerchiamo la prossima ricorrenza futura.
    private func nextDoseDescription(for medicine: Medicine) -> String {
        guard let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty else {
            return "Nessuna terapia in corso"
        }
        
        let now = Date()
        var nextDates: [Date] = []
        
        for therapy in therapies {
            // Se therapy ha una rrule, calcoliamo la prossima occorrenza
            guard let rruleString = therapy.rrule, !rruleString.isEmpty else { continue }
            
            // 1. Parsiamo la rrule
            let rule = recurrenceManager.parseRecurrenceString(rruleString)
            
            // 2. Calcoliamo la prossima data utile (funzione ipotetica: nextOccurrence)
            //    Dovresti implementarla in RecurrenceManager, facendo un calcolo basato su
            //    start_date, freq, interval, byDay, etc. e sugli orari (Dose).
            if let nextOccurrence = recurrenceManager.nextOccurrence(
                rule: rule,
                startDate: therapy.start_date ?? now,
                after: now,
                doses: therapy.doses as NSSet?
            ) {
                nextDates.append(nextOccurrence)
            }
        }
        
        // Se non troviamo alcuna prossima data
        guard let nearestDate = nextDates.sorted().first else {
            return "Nessun promemoria impostato"
        }
        
        return dateFormatter.string(from: nearestDate)
    }
}
