//
//  TherapiesIndex.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 21/02/25.
//

import SwiftUI

struct TherapiesIndex: View {

    @Environment(\.managedObjectContext) var managedObjectContext
    var medicine: Medicine = Medicine()
    @State private var therapyArray: [Therapy] = []

    // Aggiunta funzione helper per formattare la data della dose
    func formattedAssumptionDate(_ date: Date) -> String {
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
        let recurrenceManager = RecurrenceManager(context: managedObjectContext)
        
        VStack {
            ForEach(therapyArray) { therapy in
                HStack {
                    if let startDate = therapy.start_date,
                       let rrule = therapy.rrule,
                       let nextDate = recurrenceManager.nextOccurrence(
                                        rule: recurrenceManager.parseRecurrenceString(rrule),
                                        startDate: startDate,
                                        after: Date(),
                                        doses: therapy.doses as NSSet?) {
                        Text("\(formattedAssumptionDate(nextDate))")
                    }else if let startDate = therapy.start_date {
                        Text("\(formattedAssumptionDate(startDate))")
                        
                    }
                    if let nome = therapy.person.nome, let cognome = therapy.person.cognome,
                       !(nome.isEmpty && cognome.isEmpty) {
                        HStack {
                            Image(systemName: "person")
                            Text("\(nome) \(cognome)")
                        }
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            self.therapyArray = Array(medicine.therapies as? Set<Therapy> ?? [])
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

#Preview {
    TherapiesIndex()
}
