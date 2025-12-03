import SwiftUI
import CoreData

struct LogsListView: View {
    @Environment(\.managedObjectContext) private var context
    let medicine: Medicine
    
    @FetchRequest var logs: FetchedResults<Log>
    
    init(medicine: Medicine) {
        self.medicine = medicine
        _logs = FetchRequest(
            entity: Log.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Log.timestamp, ascending: false)],
            predicate: NSPredicate(format: "medicine == %@", medicine)
        )
    }
    
    var body: some View {
        List {
            if logs.isEmpty {
                Text("Nessun log disponibile.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logs, id: \.objectID) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.type ?? "Evento")
                            .font(.headline)
                        Text(dateFormatter.string(from: log.timestamp ?? Date()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let pkg = log.package {
                            Text(packageSummary(pkg))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func packageSummary(_ pkg: Package) -> String {
        let typeRaw = pkg.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity: String? = {
            if pkg.numero > 0 {
                let unitLabel = typeRaw.isEmpty ? "unità" : typeRaw.lowercased()
                return "\(pkg.numero) \(unitLabel)"
            }
            return typeRaw.isEmpty ? nil : typeRaw.capitalized
        }()
        let dosage: String? = {
            guard pkg.valore > 0 else { return nil }
            let unit = pkg.unita.trimmingCharacters(in: .whitespacesAndNewlines)
            return unit.isEmpty ? "\(pkg.valore)" : "\(pkg.valore) \(unit)"
        }()
        if let quantity, let dosage {
            return "\(quantity) da \(dosage)"
        }
        if let quantity { return quantity }
        if let dosage { return dosage }
        return "Confezione"
    }
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }
}
