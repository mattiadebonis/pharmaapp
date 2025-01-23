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

    var body: some View {
        VStack {
            let manualIntakeRegistration = options.first?.manual_intake_registration ?? false
            HStack(alignment: .top) {
                if manualIntakeRegistration {
                    Button(action:{
                        do{
                            let log = Log(context: managedObjectContext)
                            log.id = UUID()
                            log.timestamp = Date()
                            log.medicine = medicine
                            log.type = "intake"
                            
                            try managedObjectContext.save()

                        } catch {
                            print("Errore nel salvataggio di Intake: \(error.localizedDescription)")
                        }
                    }){
                        Image(systemName:"circle")
                    }
                }
                VStack(alignment: .leading, spacing: 10) {

                    HStack{
                        //Image(systemName: "pills").foregroundColor(pastelBlue)
                        Text(medicine.nome).foregroundColor(textColor).font(.title3).bold()
                        Spacer()
                    }
                    if let therapies = medicine.therapies {
                        ForEach(Array(medicine.therapies ?? []), id: \.self) { therapy in
                            HStack (alignment: .top) {
                                let frequency = therapy.rrule.map { _ in recurrenceDescription() } ?? ""
                                let startDate = therapy.start_date.map { dateFormatter.string(from: $0) } ?? ""
                                let package = "\(therapy.package.tipologia) - \(therapy.package.valore) \(therapy.package.unita) - \(therapy.package.volume)"
                                
                                Text(frequency)
                                Text(package)
                                
                                Spacer()
                            }.foregroundColor(.gray)
                            if let doses = therapy.doses {
                                ForEach(Array(doses), id: \.self) { dose in
                                    Text("Orario: \(dateFormatter.string(from: dose.time ?? Date()))")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    HStack{   
                        Image(systemName: "checkmark").foregroundColor(.green)
                        Text("Scorte al completo").foregroundColor(textColor)
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
    }

    func recurrenceDescription() -> String {
        guard let therapy = medicine.therapies?.first,
              let rrule = therapy.rrule else {
            return "Nessuna ricorrenza"
        }
        let rule = recurrenceManager.parseRecurrenceString(rrule)
        return recurrenceManager.describeRecurrence(rule: rule)
    }
}

let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    
    formatter.timeStyle = .short
    return formatter
}()

