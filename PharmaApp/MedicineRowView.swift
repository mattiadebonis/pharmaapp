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
    private func combine(day: Date, withTime time: Date) -> Date? {
        let cal = Calendar.current
        var comps = DateComponents()
        let dcDay = cal.dateComponents([.year, .month, .day], from: day)
        let dcTime = cal.dateComponents([.hour, .minute, .second], from: time)
        comps.year = dcDay.year
        comps.month = dcDay.month
        comps.day = dcDay.day
        comps.hour = dcTime.hour
        comps.minute = dcTime.minute
        comps.second = dcTime.second
        return cal.date(from: comps)
    }
    // Helper per verificare se una therapy ricorre oggi
    private func icsCode(for date: Date) -> String {
        let wd = Calendar.current.component(.weekday, from: date)
        switch wd { case 1: return "SU"; case 2: return "MO"; case 3: return "TU"; case 4: return "WE"; case 5: return "TH"; case 6: return "FR"; case 7: return "SA"; default: return "MO" }
    }
    private func occursToday(_ t: Therapy) -> Bool {
        let now = Date()
        let cal = Calendar.current
        let rule = recurrenceManager.parseRecurrenceString(t.rrule ?? "")
        let start = t.start_date ?? now
        let endOfDay = cal.date(byAdding: DateComponents(day: 1, second: -1), to: cal.startOfDay(for: now)) ?? now
        if start > endOfDay { return false }
        if let until = rule.until, cal.startOfDay(for: until) < cal.startOfDay(for: now) { return false }
        let interval = rule.interval ?? 1
        switch rule.freq.uppercased() {
        case "DAILY":
            let startSOD = cal.startOfDay(for: start)
            let todaySOD = cal.startOfDay(for: now)
            if let days = cal.dateComponents([.day], from: startSOD, to: todaySOD).day, days >= 0 {
                return days % max(1, interval) == 0
            }
            return false
        case "WEEKLY":
            let byDays = rule.byDay
            let allowed = byDays.isEmpty ? ["MO","TU","WE","TH","FR","SA","SU"] : byDays
            guard allowed.contains(icsCode(for: now)) else { return false }
            let startWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
            let todayWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            if let weeks = cal.dateComponents([.weekOfYear], from: startWeek, to: todayWeek).weekOfYear, weeks >= 0 {
                return weeks % max(1, interval) == 0
            }
            return false
        default:
            return false
        }
    }
    // MARK: - New computed helpers for UI
    private var nextDate: Date? { nextOcc?.date }
    // Dosi odierne pianificate vs assunte
    private var scheduledDosesToday: Int {
        guard !therapies.isEmpty else { return 0 }
        return therapies.reduce(0) { acc, t in
            acc + (occursToday(t) ? max(1, t.doses?.count ?? 1) : 0)
        }
    }
    private var intakeLogsToday: Int {
        let now = Date()
        let cal = Calendar.current
        guard let logs = medicine.logs else { return 0 }
        return logs.filter { $0.type == "intake" && cal.isDate($0.timestamp, inSameDayAs: now) }.count
    }
    private var scheduledTimesToday: [Date] {
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard !therapies.isEmpty else { return [] }
        var times: [Date] = []
        for t in therapies {
            guard occursToday(t) else { continue }
            if let doseSet = t.doses as? Set<Dose> {
                for d in doseSet {
                    if let dt = combine(day: today, withTime: d.time) {
                        times.append(dt)
                    }
                }
            }
        }
        return times.sorted()
    }
    private var earliestOverdueDoseTime: Date? {
        let taken = intakeLogsToday
        let times = scheduledTimesToday
        guard !times.isEmpty else { return nil }
        let pending = Array(times.dropFirst(min(taken, times.count)))
        return pending.first(where: { $0 <= Date() })
    }
    private var hasRemainingDosesToday: Bool {
        max(0, scheduledDosesToday - intakeLogsToday) > 0
    }
    private var isDoseToday: Bool {
        guard let d = nextDate else { return false }
        return Calendar.current.isDateInToday(d) && hasRemainingDosesToday
    }
    private var isLowStock: Bool {
        guard let opt = option else { return false }
        return medicine.isInEsaurimento(option: opt, recurrenceManager: recurrenceManager)
    }

    private var coverageThreshold: Int {
        Int(option?.day_threeshold_stocks_alarm ?? 7)
    }

    // True se non ci sono terapie e le unità disponibili sono sotto 5
    private var isLowUnitsNoTherapy: Bool {
        guard therapies.isEmpty, let rem = remainingUnits else { return false }
        return rem < 5
    }

    // Messaggio e stile per warning scorte (sotto soglia copertura o poche unità senza terapie)
    private var stocksWarning: (text: String, color: Color, icon: String)? {
        // Caso con terapie: sotto soglia di copertura
        if !therapies.isEmpty {
            if let days = autonomyDays {
                if days <= 0 {
                    return ("Scorte esaurite", .red, "exclamationmark.triangle.fill")
                } else if days < coverageThreshold {
                    return ("Copertura bassa: \(days) giorni", .orange, "exclamationmark.triangle.fill")
                }
            }
            return nil
        }
        // Caso senza terapie: poche unità
        if let rem = remainingUnits {
            if rem <= 0 {
                return ("Scorte esaurite", .red, "exclamationmark.triangle.fill")
            } else if rem < 5 {
                return ("Scorte basse: \(rem) unità", .orange, "exclamationmark.triangle.fill")
            }
        }
        return nil
    }
    // Mostra l’ora in alto a destra solo se resta una dose oggi
    private var rightPillText: String? {
        guard let d = nextDate, isDoseToday else { return nil }
        return time(d)
    }
    // Testo grigio sotto il nome, solo se NON è per oggi (o l'ultima dose di oggi è già stata assunta)
    private var nextDescription: String? {
        guard let d = nextDate, !isDoseToday else { return nil }
        let c = Calendar.current
        if let w = c.date(byAdding: .day, value: lookAheadDays, to: Date()), d <= w {
            let fmt = DateFormatter(); fmt.locale = Locale(identifier: "it_IT"); fmt.setLocalizedDateFormatFromTemplate("EEE HH:mm")
            return "Prossima: \(fmt.string(from: d))"
        }
        let rel = RelativeDateTimeFormatter(); rel.locale = Locale(identifier: "it_IT"); rel.unitsStyle = .full
        let relText = rel.localizedString(for: d, relativeTo: Date())
        return "Prossima: \(relText)"
    }

    // Calcolo unità rimanenti quando non ci sono terapie
    private var remainingUnits: Int? {
        guard therapies.isEmpty else { return nil }
        guard let pkg = getPackage(for: medicine), let logs = medicine.logs else { return nil }
        let purchases = logs.filter { $0.type == "purchase" && $0.package == pkg }.count
        let intakes   = logs.filter { $0.type == "intake" && $0.package == pkg }.count
        return purchases * Int(pkg.numero) - intakes
    }
    // Stato scorte: testo neutro se non in warning
    private var stocksStatusText: String? {
        if stocksWarning != nil { return nil }
        if !therapies.isEmpty {
            if let days = autonomyDays { return "Copertura: \(days) giorni" }
            return nil
        } else {
            if let rem = remainingUnits { return "Unità rimanenti: \(rem)" }
            return nil
        }
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
            if let overdue = earliestOverdueDoseTime {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(time(overdue))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.12)))
                .accessibilityLabel("Assunzione in ritardo alle \(time(overdue))")
            } else if let pill = rightPillText {
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
            if let desc = nextDescription {
                Text(desc)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var warningOrStocksRow: some View {
        Group {
            if let warn = stocksWarning {
                HStack(spacing: 6) {
                    Image(systemName: warn.icon)
                        .foregroundStyle(warn.color)
                    Text(warn.text)
                        .font(.footnote)
                        .foregroundStyle(warn.color)
                }
                .accessibilityLabel("Avviso scorte: \(warn.text)")
            } else if let text = stocksStatusText {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsRow: some View {
        Group {
            if hasRemainingDosesToday {
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
