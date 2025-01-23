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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appViewModel: AppViewModel

    var medicine: Medicine
    var package: Package
    
    @StateObject var medicineFormViewModel: MedicineFormViewModel

    init(
        medicine: Medicine,
        package: Package,
        context: NSManagedObjectContext
    ) {
        self.medicine = medicine
        self.package = package
        _medicineFormViewModel = StateObject(
            wrappedValue: MedicineFormViewModel(context: context)
        )
        
    }

    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    @State private var selectedTherapy: Therapy?

    var body: some View {
        NavigationView{
            Form{
                Section(){
                    if let therapies = medicine.therapies{
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
                                    .onTapGesture {
                                        selectedTherapy = therapy
                                    }
                                }
                            }
                        }
                    }
                }
                Section(){
                    Button(action: {
                        medicineFormViewModel.saveForniture(
                            medicine: medicine,
                            package: package
                        )
                    }) {
                        Text("Aggiungi scorte")
                    }
                }

                
            }
            .navigationTitle("\(medicine.nome) - \(package.tipologia) \(package.valore) \(package.unita) \(package.volume)")
        }
    }

    private func recurrenceDescription(therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        return recurrenceManager.describeRecurrence(rule: rule)
    }
}
