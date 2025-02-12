//
//  MedicineFormView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 23/01/25.
//

import SwiftUI
import CoreData

struct MedicineFormView: View {

    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appViewModel: AppViewModel
    @StateObject private var medicineFormViewModel = MedicineFormViewModel(context: PersistenceController.shared.container.viewContext)
    var medicine: Medicine
    var package: Package
    
    private var currentOption: Option? { options.first }
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    @State private var selectedTherapy: Therapy?

    // Computed property per determinare lo status della prescrizione
    private var prescriptionStatus: String? {
        guard let option = currentOption, medicine.obbligo_ricetta else { return nil }
        let inEsaurimento = medicine.isInEsaurimento(option: option, recurrenceManager: recurrenceManager)
        guard inEsaurimento else { return nil }
        
        if medicine.hasPendingNewPrescription() {
            return "Comprato"
        } else if medicine.hasNewPrescritpionRequest() {
            return "Ricetta arrivata"
        } else {
            return "Ricetta richiesta"
        }
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                
                if let status = prescriptionStatus {
                    HStack {
                        Text("Stato prescrizione: \(status)")
                            .foregroundColor(.blue)
                        prescriptionActionButton()
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                
                
                // Se sono presenti delle Therapy, mostriamo l'elenco
                if let therapies = medicine.therapies, !therapies.isEmpty {
                    ForEach(Array(therapies), id: \.self) { therapy in
                        if therapy.rrule != nil {
                            NavigationLink(destination:
                                TherapyFormView(
                                    medicine: medicine,
                                    package: package,
                                    context: context
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(alignment: .top) {
                                        let frequency = therapy.rrule.map { _ in recurrenceDescription(therapy: therapy) } ?? ""
                                        let startDate = therapy.start_date.map { dateFormatter.string(from: $0) } ?? ""
                                        Text(therapy.importance ?? "")
                                        Text(frequency)
                                        Spacer()
                                    }
                                    .foregroundColor(.gray)
                                    
                                    if let doses = therapy.doses {
                                        ForEach(Array(doses), id: \.self) { dose in
                                            Text("Orario: \(dateFormatter.string(from: dose.time ?? Date()))")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                if let option = currentOption, option.manual_intake_registration {
                    Button(action: {
                        medicineFormViewModel.addIntake(for: medicine)
                    }) {
                        Image(systemName: "pills")
                        Text("Assunto")
                    }
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                Button(action: {
                    medicineFormViewModel.saveForniture(medicine: medicine, package: package)
                }) {
                    Image(systemName: "cart")
                    Text("Comprato")
                        
                }
                .bold()
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.horizontal)
                
            }
            .navigationTitle("\(medicine.nome ?? "") - \(package.tipologia) \(package.valore) \(package.unita) \(package.volume)")
        }
    }
    
    // Funzione di utilità per descrivere la ricorrenza di una Therapy
    private func recurrenceDescription(therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        return recurrenceManager.describeRecurrence(rule: rule)
    }
    
    // ViewBuilder per il pulsante d'azione in base allo status della prescrizione
    @ViewBuilder
    private func prescriptionActionButton() -> some View {
        if let status = prescriptionStatus {
            switch status {
            case "Ricetta richiesta":
                Button(action: {
                    medicineFormViewModel.addNewPrescriptionRequest(for: medicine)
                }) {
                    Text("Richiedi ricetta")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
            case "Ricetta arrivata":
                Button(action: {
                    medicineFormViewModel.addNewPrescription(for: medicine)
                }) {
                    Text("Conferma ricetta")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.green)
                        .cornerRadius(8)
                }
            case "Comprato":
                Button(action: {
                    medicineFormViewModel.addPurchase(for: medicine)
                }) {
                    Text("Compra")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            default:
                EmptyView()
            }
        }
    }
}