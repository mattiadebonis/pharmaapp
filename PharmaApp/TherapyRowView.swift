//
//  TherapyRowView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 28/12/24.
//

import SwiftUI

struct TherapyRowView: View {

    @Environment(\.managedObjectContext) var managedObjectContext


    var medicine: Medicine

    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    let textColor = Color(red: 47/255, green: 47/255, blue: 47/255, opacity: 1.0)

    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)

    var body: some View {
        VStack {
            HStack(alignment: .top) {
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
                VStack(alignment: .leading) {
                    HStack{
                        Image(systemName: "pills").foregroundColor(pastelBlue)
                        Text(medicine.nome).foregroundColor(textColor)
                    }
                    if let therapy = medicine.therapies?.first {
                        HStack (alignment: .top) {
                            let rrule = therapy.rrule.map { _ in recurrenceDescription() } ?? ""
                            let startDate = therapy.start_date.map { dateFormatter.string(from: $0) } ?? ""
                            // let package = medicine.packages.first.map {_ in "\(package.tipologia) - \(package.valore) \(package.unita) - \(package.volume)"} ?? ""
                            
                            let combinedString = "\(startDate), \(rrule)"
                            Text(combinedString)
                            Spacer()
                        }.foregroundColor(.gray)
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
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

