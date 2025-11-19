import SwiftUI
import CoreData

struct MedicineRowView: View {
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    
    // MARK: - Costanti
    private let lookAheadDays = 7
    // MARK: - Input
    var medicine: Medicine
    var isSelected: Bool = false
    var isInSelectionMode: Bool = false
    enum RowSection { case purchase, tuttoOk }
    
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
    private var coverageThreshold: Int {
        Int(option?.day_threeshold_stocks_alarm ?? 7)
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
    
    // Orario di assunzione da mostrare in "Oggi":
    // 1) se c'è una dose in ritardo, mostra quell'orario
    // 2) altrimenti, se la prossima dose è oggi, mostra l'orario
    // Calcolo unità rimanenti quando non ci sono terapie
    private var remainingUnits: Int? {
        guard therapies.isEmpty else { return nil }
        return medicine.remainingUnitsWithoutTherapy()
    }
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                leadingIcon
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(medicineSubtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                stockColumn
            }
            badgesRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(selectionBorderColor, lineWidth: selectionBorderWidth)
        )
    }
    
    private var hasTherapiesFlag: Bool { !therapies.isEmpty }
    private var displayName: String {
        let trimmed = medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Medicinale" : trimmed
    }
    
    private var medicineSubtitleText: String {
        var parts: [String] = []
        if let descriptor = packageDescriptor {
            parts.append(descriptor)
        }
        if let window = therapyWindowDescription {
            parts.append(window)
        } else {
            parts.append(hasTherapiesFlag ? "Terapia attiva" : "Uso al bisogno")
        }
        return parts.joined(separator: " · ")
    }
    
    private var leadingIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(iconGradient)
                .frame(width: 56, height: 56)
            Image(systemName: leadingIconSymbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
    
    private var leadingIconSymbol: String {
        if stocksWarning != nil {
            return "exclamationmark.triangle.fill"
        }
        if hasTherapiesFlag {
            return "pills.fill"
        }
        return "cross.case.fill"
    }
    
    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: [leadingAccentColor, leadingAccentColor.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var leadingAccentColor: Color {
        if let warningColor = stocksWarning?.color {
            return warningColor
        }
        if earliestOverdueDoseTime != nil {
            return .orange
        }
        if isDoseToday {
            return .blue
        }
        return hasTherapiesFlag ? .teal : .green
    }
    
    private var stockColumn: some View {
        let display = stockDisplay
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: display.icon)
                Text(display.primary)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundStyle(display.color)
            
            Text(display.secondary)
                .font(.caption)
                .foregroundStyle(display.color.opacity(0.85))
        }
        .frame(minWidth: 92, alignment: .trailing)
    }
    
    private var badgesRow: some View {
        HStack(spacing: 8) {
            badge(for: therapyBadgeData)
            if let stockBadge = stockStatusBadge {
                badge(for: stockBadge)
            }
            Spacer()
        }
    }
    
    private struct BadgeData {
        let icon: String
        let text: String
        let color: Color
    }
    
    private func badge(for data: BadgeData) -> some View {
        Label(data.text, systemImage: data.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(data.color.opacity(0.15))
            )
            .foregroundStyle(data.color)
    }
    
    private var therapyBadgeData: BadgeData {
        if let overdue = earliestOverdueDoseTime {
            return BadgeData(icon: "bell.badge.fill", text: "Dose saltata \(time(overdue))", color: .red)
        }
        if isDoseToday, let next = nextDate {
            return BadgeData(icon: "clock.fill", text: "Dose oggi \(time(next))", color: .blue)
        }
        if hasTherapiesFlag {
            return BadgeData(icon: "stethoscope", text: "Terapia programmata", color: .teal)
        }
        return BadgeData(icon: "staroflife", text: "Uso al bisogno", color: .secondary)
    }
    
    private var stockStatusBadge: BadgeData? {
        guard let warning = stocksWarning else { return nil }
        return BadgeData(icon: warning.icon, text: warning.text, color: warning.color)
    }
    
    private var packageDescriptor: String? {
        guard let pkg = primaryPackage else { return nil }
        let type = pkg.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
        if !type.isEmpty { return type.capitalized }
        let unit = pkg.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unit.isEmpty { return unit.capitalized }
        return nil
    }
    
    private var primaryPackage: Package? {
        guard !medicine.packages.isEmpty else { return nil }
        return medicine.packages.sorted { $0.numero > $1.numero }.first
    }
    
    private var therapyWindowDescription: String? {
        guard hasTherapiesFlag else { return nil }
        guard let next = nextDate else { return nil }
        if Calendar.current.isDateInToday(next) {
            let hour = Calendar.current.component(.hour, from: next)
            switch hour {
            case 5..<12: return "Terapia mattutina"
            case 12..<18: return "Terapia pomeridiana"
            case 18..<24: return "Terapia serale"
            default: return "Terapia notturna"
            }
        }
        return "Dose \(day(next).lowercased())"
    }
    
    private var stockDisplay: StockDisplay {
        if let warning = stocksWarning {
            return StockDisplay(icon: warning.icon, primary: stockValueText, secondary: warning.text, color: warning.color)
        }
        if let autonomy = autonomyDays {
            let clamped = max(0, autonomy)
            if clamped == 0 {
                return StockDisplay(icon: "exclamationmark.triangle.fill", primary: "0 gg", secondary: "Scorte finite", color: .red)
            }
            if clamped < coverageThreshold {
                return StockDisplay(icon: "hourglass", primary: "\(clamped) gg", secondary: "Copertura ridotta", color: .orange)
            }
            return StockDisplay(icon: "shippingbox.fill", primary: "\(clamped) gg", secondary: "Scorte ok", color: .teal)
        }
        if let units = remainingUnits {
            let clamped = max(0, units)
            if clamped == 0 {
                return StockDisplay(icon: "exclamationmark.triangle.fill", primary: "0 u", secondary: "Scorte finite", color: .red)
            } else if clamped < 5 {
                return StockDisplay(icon: "square.stack.3d.up.fill", primary: "\(clamped) u", secondary: "Integra presto", color: .orange)
            } else {
                return StockDisplay(icon: "square.stack.3d.up.fill", primary: "\(clamped) u", secondary: "Scorte ok", color: .blue)
            }
        }
        return StockDisplay(icon: "questionmark.circle", primary: "—", secondary: "Nessuna informazione", color: .secondary)
    }
    
    private var stockValueText: String {
        if let days = autonomyDays {
            return "\(max(0, days)) gg"
        }
        if let remaining = remainingUnits {
            return "\(max(0, remaining)) u"
        }
        return "—"
    }
    
    private struct StockDisplay {
        let icon: String
        let primary: String
        let secondary: String
        let color: Color
    }
    
    private var selectionBorderWidth: CGFloat {
        guard isInSelectionMode else { return 0 }
        return isSelected ? 2.5 : 1
    }
    
    private var selectionBorderColor: Color {
        guard isInSelectionMode else { return .clear }
        return isSelected ? .accentColor : .accentColor.opacity(0.35)
    }
}

// MARK: - Convenienza
private extension Medicine {
    var totalLeftover: Int {
        Int((therapies as? Set<Therapy> ?? []).reduce(0) { $0 + $1.leftover() })
    }
}
