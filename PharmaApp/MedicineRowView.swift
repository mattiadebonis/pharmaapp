//
//  TherapyRowView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 28/12/24.
//

import SwiftUI

struct MedicineRowView: View {

    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>

    var medicine: Medicine
    let pastelGreen = Color(red: 179/255, green: 220/255, blue: 190/255, opacity: 1.0)
    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    let textColor = Color(red: 47/255, green: 47/255, blue: 47/255, opacity: 1.0)

    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    @State private var selectedTherapy: Therapy?

    var body: some View {
        VStack {
            let manualIntakeRegistration = options.first?.manual_intake_registration ?? false
            HStack(alignment: .top) {
                if manualIntakeRegistration {
                    Button(action: {
                        do {
                            let log = Log(context: managedObjectContext)
                            log.id = UUID()
                            log.timestamp = Date()
                            log.medicine = medicine
                            log.type = "intake"
                            
                            try managedObjectContext.save()
                        } catch {
                            print("Errore nel salvataggio di Intake: \(error.localizedDescription)")
                        }
                    }) {
                        Image(systemName: "circle")
                    }
                }
            
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(medicine.nome ?? "")
                            .foregroundColor(textColor)
                            .font(.title3)
                            .bold()
                        Spacer()
                    }
                    if let therapies = medicine.therapies {
                        ForEach(Array(therapies), id: \.self) { therapy in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .top) {
                                    let frequency = therapy.rrule.map { _ in recurrenceDescription(therapy: therapy) } ?? ""
                                    let startDate = therapy.start_date.map { dateFormatter.string(from: $0) } ?? ""
                                    let package = "\(therapy.package.tipologia) - \(therapy.package.valore) \(therapy.package.unita) - \(therapy.package.volume)"
                                    
                                    Text(frequency)
                                    Text(package)
                                    
                                    Spacer()
                                }
                                .foregroundColor(.gray)
                                
                                if let doses = therapy.doses {
                                    ForEach(Array(doses), id: \.self) { dose in
                                        Text("\(dateFormatter.string(from: dose.time ?? Date()))")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .onTapGesture {
                                selectedTherapy = therapy
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                        Text("Scorte al completo")
                            .foregroundColor(textColor)
                    }
                }
                Spacer()
            }
        }
         .padding(20)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 220/255, green: 220/255, blue: 220/255), lineWidth: 1)
        )
        .cornerRadius(8)
        .sheet(item: $selectedTherapy) { therapy in
            MedicineFormView(
                medicine: medicine,
                package: therapy.package,
                context: managedObjectContext
            )
        }
    }

    private func recurrenceDescription(therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        return recurrenceManager.describeRecurrence(rule: rule)
    }
}
