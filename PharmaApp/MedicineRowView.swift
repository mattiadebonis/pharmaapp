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
        medicine.stockThreshold(option: option)
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
        HStack(alignment: .top, spacing: 12) {
            leadingIcon
            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                infoPills
                if hasBadges {
                    badgesRow
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay {
            if isInSelectionMode {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selectionBorderColor, lineWidth: selectionBorderWidth)
            }
        }
    }
    
    private var hasTherapiesFlag: Bool { !therapies.isEmpty }
    private var displayName: String {
        let trimmed = medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Medicinale" : trimmed
        return camelCase(base)
    }
    
    private var firstPackageInfo: String? {
        guard let pkg = medicine.packages.first else { return nil }
        return packageLabel(pkg)
    }
    
    private func packageLabel(_ pkg: Package) -> String? {
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
        return nil
    }
    
    private func camelCase(_ text: String) -> String {
        let lowered = text.lowercased()
        return lowered
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
    
    private var leadingIcon: some View {
        Image(systemName: leadingIconSymbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(leadingAccentColor)
            .frame(width: 28, height: 28, alignment: .topLeading)
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
    
    private var infoPills: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                pill(for: therapyInfoChip)
            }
            HStack(spacing: 8) {
                pill(for: stockChip)
                /* if let packageChip = packageChip {
                    pill(for: packageChip)
                } */
            }
        }
    }

    private struct InfoChip {
        let icon: String?
        let text: String
        let color: Color
    }

    private func pill(for data: InfoChip) -> some View {
        HStack(spacing: 6) {
            if let icon = data.icon {
                Image(systemName: icon)
                    .foregroundStyle(data.color)
            }
            Text(data.text)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var therapyInfoChip: InfoChip {
        guard hasTherapiesFlag else {
            return InfoChip(icon: "staroflife", text: "Uso al bisogno", color: .teal)
        }
        let nextText: String = {
            guard let next = nextDate else { return "nessuna dose programmata" }
            let cal = Calendar.current
            if cal.isDateInToday(next) {
                return "oggi alle \(time(next))"
            }
            if cal.isDateInTomorrow(next) {
                return "domani"
            }
            if let overm = cal.date(byAdding: .day, value: 2, to: Date()), cal.isDate(next, inSameDayAs: overm) {
                return "dopodomani"
            }
            return day(next).lowercased()
        }()
        let personText = therapyPersonSummary.map { "per \($0)" } ?? ""
        let text = [nextText, personText].filter { !$0.isEmpty }.joined(separator: " · ")
        let isToday = nextDate.map { Calendar.current.isDateInToday($0) } ?? false
        let color: Color = isToday ? .blue : .teal
        return InfoChip(icon: "staroflife", text: text, color: color)
    }

    private var stockChip: InfoChip {
        let display = stockDisplay
        return InfoChip(
            icon: "square.stack.3d.up.fill",
            text: "\(display.primary) · \(display.secondary)",
            color: display.color
        )
    }

    private var packageChip: InfoChip? {
        guard let descriptor = packageDescriptor else { return nil }
        return InfoChip(icon: nil, text: descriptor, color: .secondary)
    }
    
    private var badgesRow: some View {
        HStack(spacing: 8) {
            if let therapyBadge = therapyBadgeData {
                badge(for: therapyBadge)
            }
            Spacer()
        }
    }
    
    private struct BadgeData {
        let icon: String
        let text: String
        let color: Color
    }

    private var hasBadges: Bool {
        therapyBadgeData != nil
    }
    
    private func badge(for data: BadgeData) -> some View {
        HStack(spacing: 6) {
            Image(systemName: data.icon)
                .foregroundStyle(data.color)
            Text(data.text)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
    
    private var therapyBadgeData: BadgeData? {
        if let overdue = earliestOverdueDoseTime {
            return BadgeData(icon: "bell.badge.fill", text: "Dose saltata \(time(overdue))", color: .red)
        }
        return nil
    }

    private var therapyPersonSummary: String? {
        let rawNames = therapies.compactMap { therapyPersonName($0) }.filter { !$0.isEmpty }
        guard !rawNames.isEmpty else { return nil }
        var seen = Set<String>()
        var unique: [String] = []
        for name in rawNames where seen.insert(name).inserted {
            unique.append(name)
        }
        if unique.count == 1 { return unique.first }
        if unique.count == 2 { return "\(unique[0]) e \(unique[1])" }
        let firstTwo = unique.prefix(2).joined(separator: ", ")
        return "\(firstTwo) +\(unique.count - 2)"
    }

    private func therapyPersonName(_ therapy: Therapy) -> String? {
        let first = (therapy.person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (therapy.person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let components = [first, last].filter { !$0.isEmpty }
        return components.joined(separator: " ")
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
