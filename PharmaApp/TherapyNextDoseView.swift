import SwiftUI

struct TherapyNextDoseView: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext
    
    var medicine: Medicine
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
        
        VStack(alignment: .leading, spacing: 4) {
            
            // Riga 1: Nome del Farmaco + Badge
            
            // Riga 2: Numero terapie attive + Prossima dose
            HStack{
                let activeTherapiesCount = therapyArray.count
                //Text("\(activeTherapiesCount) terapie attive")
                
                // Trova la prossima dose “minima” tra tutte le therapy di questo farmaco
                // (la più vicina al momento attuale)
                if let earliestDose = findEarliestNextDose(in: therapyArray, using: recurrenceManager) {
                    Text("\(formattedAssumptionDate(earliestDose))")
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .onAppear {
            // Carico le therapy associate al Medicine
            self.therapyArray = Array(medicine.therapies as? Set<Therapy> ?? [])
        }
    }
    
    /// Trova la prima dose futura disponibile tra tutte le therapy.
    /// Restituisce la data più vicina (se esiste).
    private func findEarliestNextDose(in therapies: [Therapy],
                                      using manager: RecurrenceManager) -> Date? {
        var nextDates: [Date] = []
        
        for therapy in therapies {
            if let startDate = therapy.start_date,
               let rrule = therapy.rrule {
                let rule = manager.parseRecurrenceString(rrule)
                
                if let nextDate = manager.nextOccurrence(
                    rule: rule,
                    startDate: startDate,
                    after: Date(),
                    doses: therapy.doses as NSSet?
                ) {
                    nextDates.append(nextDate)
                }
            }
        }
        
        // Ritorna la minima (più vicina a oggi) se ce n’è almeno una
        return nextDates.min()
    }
}

#Preview {
    TherapyNextDoseView(medicine: Medicine())
}
