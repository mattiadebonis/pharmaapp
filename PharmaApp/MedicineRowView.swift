import SwiftUI
import CoreData

struct MedicineRowView: View {
    // MARK: - Environment & State
    @Environment(\.managedObjectContext) private var moc
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @EnvironmentObject private var appVM: AppViewModel
    
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    @StateObject private var rowVM = MedicineRowViewModel(managedObjectContext: PersistenceController.shared.container.viewContext)
    
    // MARK: - Costanti
    private let lookAheadDays = 7
    
    // MARK: - Input
    var medicine: Medicine
    var isSelected: Bool
    var toggleSelection: () -> Void
    
    // MARK: - Computed
    private var option: Option? { options.first }
    private var therapies: Set<Therapy> { medicine.therapies as? Set<Therapy> ?? [] }
    
    private var autonomyDays: Int? {
        guard !therapies.isEmpty else { return nil }
        let res = therapies.reduce(into: (left: 0.0, daily: 0.0)) { acc, t in
            acc.left  += Double(t.leftover())
            acc.daily += t.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        }
        guard res.daily > 0 else { return nil }
        return Int(res.left / res.daily)
    }
    private var autonomyColor: Color {
        guard let d = autonomyDays else { return .gray }
        return d < 7 ? .red : (d < 14 ? .orange : .blue)
    }
    
    private struct Occ { let therapy: Therapy; let date: Date }
    private var upcoming: [Occ] {
        guard !therapies.isEmpty else { return [] }
        let limit = Calendar.current.date(byAdding: .day, value: lookAheadDays, to: Date())!
        return therapies.compactMap { t in
            guard let d = recurrenceManager.nextOccurrence(
                rule: recurrenceManager.parseRecurrenceString(t.rrule ?? ""),
                startDate: t.start_date ?? Date(),
                after: Date(),
                doses: t.doses as NSSet?
            ) else { return nil }
            return d <= limit ? Occ(therapy: t, date: d) : nil
        }
        .sorted { $0.date < $1.date }
    }
    private var nextOcc: Occ? { upcoming.first }
    
    // MARK: - Helpers
    private func day(_ d: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(d)      { return "Oggi" }
        if c.isDateInTomorrow(d)   { return "Domani" }
        if let overm = c.date(byAdding: .day, value: 2, to: Date()),
           c.isDate(d, inSameDayAs: overm) { return "Dopodomani" }
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d)
    }
    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: d)
    }
    // MARK: - New computed helpers for UI
    private var nextDate: Date? { nextOcc?.date }
    private var isDoseToday: Bool {
        guard let d = nextDate else { return false }
        return Calendar.current.isDateInToday(d)
    }
    private var isLowStock: Bool {
        guard let opt = option else { return false }
        return medicine.isInEsaurimento(option: opt, recurrenceManager: recurrenceManager)
    }
    private var rightPillText: String? {
        guard let d = nextDate else { return nil }
        if isDoseToday { return time(d) }
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "it_IT"); fmt.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return fmt.string(from: d)
    }
    private var nextDescription: String? {
        guard let d = nextDate else { return nil }
        let c = Calendar.current
        if c.isDateInToday(d) {
            return "Prossima: oggi alle \(time(d))"
        }
        if let w = c.date(byAdding: .day, value: 7, to: Date()), d <= w {
            let fmt = DateFormatter(); fmt.locale = Locale(identifier: "it_IT"); fmt.setLocalizedDateFormatFromTemplate("EEE HH:mm")
            return "Prossima: \(fmt.string(from: d))"
        }
        let rel = RelativeDateTimeFormatter(); rel.locale = Locale(identifier: "it_IT"); rel.unitsStyle = .full
        let relText = rel.localizedString(for: d, relativeTo: Date())
        return "Prossimo: \(relText)"
    }
    private var stockPercent: Int? {
        guard let opt = option, let days = autonomyDays else { return nil }
        let threshold = Int(opt.day_threeshold_stocks_alarm)
        if threshold <= 0 { return nil }
        return max(0, min(100, Int((Double(days) / Double(threshold)) * 100)))
    }
    private var isCriticalStock: Bool {
        guard let p = stockPercent else { return false }
        return p <= 25
    }
    private var stocksLineText: String? {
        guard let p = stockPercent else { return nil }
        var text = "Scorte ~\(p)%"
        if isCriticalStock { text += " • in esaurimento" }
        // Se non è per "oggi", aggiungo anche la prossima
        if !isDoseToday, let d = nextDate {
            let fmt = DateFormatter(); fmt.locale = Locale(identifier: "it_IT"); fmt.setLocalizedDateFormatFromTemplate("EEE HH:mm")
            text += " • Prossima: \(fmt.string(from: d))"
        }
        return text
    }

    private func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
                return package
            }
        }
        if let package = medicine.packages.first { return package }
        return nil
    }
    
    // MARK: - Body
    var body: some View {
        card
            .padding(.horizontal, 16)
    }
    
    // MARK: - Card
    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow
            subtitleRow
            warningOrStocksRow
            actionsRow
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Sub-views (nuovo layout)
    private var topRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(medicine.nome)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer(minLength: 8)
            if let pill = rightPillText {
                Text(pill)
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            }
        }
    }

    private var subtitleRow: some View {
        Group {
            if !isLowStock, let desc = nextDescription {
                Text(desc)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var warningOrStocksRow: some View {
        Group {
            if isLowStock, let stocksText = stocksLineText {
                HStack(spacing: 6) {
                    if isCriticalStock { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red) }
                    Text(stocksText)
                }
                .font(.footnote)
                .foregroundColor(isCriticalStock ? .red : .secondary)
            }
        }
    }

    private var actionsRow: some View {
        Group {
            if isDoseToday {
                HStack(spacing: 8) {
                    Button {
                        let pkg = getPackage(for: medicine)
                        rowVM.addIntake(for: medicine, package: pkg)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("Assunto", systemImage: "checkmark")
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    }
                    Spacer()
                    Button {
                        let pkg = getPackage(for: medicine)
                        rowVM.addPurchase(for: medicine, package: pkg)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("Compra", systemImage: "bag")
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Convenienza
private extension Medicine {
    var totalLeftover: Int {
        Int((therapies as? Set<Therapy> ?? []).reduce(0) { $0 + $1.leftover() })
    }
}
