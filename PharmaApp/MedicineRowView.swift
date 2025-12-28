import SwiftUI
import CoreData

struct MedicineRowView: View {
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    
    // MARK: - Costanti
    // MARK: - Input
    @ObservedObject var medicine: Medicine
    var isSelected: Bool = false
    var isInSelectionMode: Bool = false
    enum RowSection { case purchase, tuttoOk }
    
    // MARK: - Computed
    private var option: Option? { options.first }
    private var therapies: Set<Therapy> { medicine.therapies as? Set<Therapy> ?? [] }
    private var totalDoseCount: Int {
        guard !therapies.isEmpty else { return 0 }
        return therapies.reduce(0) { $0 + ($1.doses?.count ?? 0) }
    }
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
        let now = Date()
        return therapies.compactMap { t in
            guard let d = nextUpcomingDoseDate(for: t, now: now) else { return nil }
            return Occ(therapy: t, date: d)
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
                    .font(.title3.weight(.semibold))
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

    private enum StockLevel {
        case empty, low, ok
    }

    private var leadingIconName: String {
        if let warning = stocksWarning {
            return warning.icon
        }
        return "pills.fill"
    }

    private var leadingIconColor: Color {
        if let warning = stocksWarning {
            return warning.color
        }
        switch stockLevel {
        case .empty:
            return .red
        case .low:
            return .orange
        case .ok:
            return therapies.isEmpty ? .green : .blue
        }
    }

    private var stockLevel: StockLevel {
        if let warning = stocksWarning {
            // Map warnings back to severity.
            if warning.color == .red {
                return .empty
            }
            if warning.color == .orange {
                return .low
            }
        }

        if !therapies.isEmpty {
            if let days = autonomyDays {
                if days <= 0 { return .empty }
                if days < coverageThreshold { return .low }
            }
            return .ok
        }

        if let rem = remainingUnits {
            if rem <= 0 { return .empty }
            if rem < 5 { return .low }
            return .ok
        }

        return .ok
    }

    private var leadingIcon: some View {
        Image(systemName: leadingIconName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(leadingIconColor)
            .frame(width: 28, height: 28, alignment: .center)
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
    
    private func nextOccurrence(for therapy: Therapy) -> Date? {
        recurrenceManager.nextOccurrence(
            rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
            startDate: therapy.start_date ?? Date(),
            after: Date(),
            doses: therapy.doses as NSSet?
        )
    }

    private func intakeCountToday(for therapy: Therapy, now: Date) -> Int {
        let calendar = Calendar.current
        let logsToday = (medicine.logs ?? []).filter { $0.type == "intake" && calendar.isDate($0.timestamp, inSameDayAs: now) }
        let assigned = logsToday.filter { $0.therapy == therapy }.count
        if assigned > 0 { return assigned }

        let unassigned = logsToday.filter { $0.therapy == nil }
        if therapies.count == 1 { return unassigned.count }
        return unassigned.filter { $0.package == therapy.package }.count
    }

    private func scheduledTimesToday(for therapy: Therapy, now: Date) -> [Date] {
        guard occursToday(therapy) else { return [] }
        let today = Calendar.current.startOfDay(for: now)
        guard let doseSet = therapy.doses as? Set<Dose>, !doseSet.isEmpty else { return [] }
        return doseSet.compactMap { dose in
            combine(day: today, withTime: dose.time)
        }.sorted()
    }

    private func nextUpcomingDoseDate(for therapy: Therapy, now: Date) -> Date? {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let startDate = therapy.start_date ?? now

        let calendar = Calendar.current
        let timesToday = scheduledTimesToday(for: therapy, now: now)
        if calendar.isDateInToday(now), !timesToday.isEmpty {
            let takenCount = intakeCountToday(for: therapy, now: now)
            if takenCount >= timesToday.count {
                let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: now)) ?? now
                return recurrenceManager.nextOccurrence(rule: rule, startDate: startDate, after: endOfDay, doses: therapy.doses as NSSet?)
            }
            let pending = Array(timesToday.dropFirst(min(takenCount, timesToday.count)))
            if let nextToday = pending.first(where: { $0 > now }) {
                return nextToday
            }
        }

        return recurrenceManager.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: therapy.doses as NSSet?)
    }
    
    private func personName(for therapy: Therapy) -> String? {
        let person = therapy.person
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if last.isEmpty, first.lowercased() == "persona" { return nil }
        let parts = [first, last].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
    
    private var therapyChipIconColor: Color { .indigo }
    private var stockChipIconColor: Color { .cyan }

    private struct InfoChip: Identifiable {
        let id = UUID()
        let icon: String?
        let text: String
        let color: Color
    }

    private var infoPills: some View {
        let therapyChips = therapyInfoChips
        return VStack(alignment: .leading, spacing: 6) {
            if !therapyChips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(therapyChips) { chip in
                        pill(for: chip)
                    }
                }
            }
            HStack(spacing: 8) {
                pill(for: stockChip)
            }
        }
    }

    private func pill(for data: InfoChip) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if let icon = data.icon {
                Image(systemName: icon)
                    .foregroundStyle(data.color)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
            }
            Text(data.text)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var therapyInfoChips: [InfoChip] {
        guard !therapies.isEmpty else { return [] }
        let therapyCount = therapies.count
        let text = therapyCount == 1 ? "1 terapia" : "\(therapyCount) terapie"
        return [InfoChip(icon: nil, text: text, color: therapyChipIconColor)]
    }

    private var stockChip: InfoChip {
        let text: String = {
            if let days = autonomyDays {
                let clamped = max(0, days)
                let suffix = clamped == 1 ? "per 1 giorno" : "per \(clamped) giorni"
                if let label = stockTypeLabel {
                    return "\(label) \(suffix)"
                }
                return "Scorte \(suffix)"
            }
            if let units = remainingUnits {
                let clamped = max(0, units)
                return "\(clamped) \(stockUnitLabel)"
            }
            let display = stockDisplay
            return "\(display.primary) · \(display.secondary)"
        }()
        return InfoChip(icon: nil, text: text, color: stockChipIconColor)
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
        .font(.callout)
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
        if last.isEmpty, first.lowercased() == "persona" { return nil }
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

    private var stockTypeLabel: String? {
        guard let pkg = primaryPackage else { return nil }
        let candidates = [
            pkg.tipologia,
            pkg.unita,
            packageDescriptor
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        for candidate in candidates {
            if let container = extractPackageContainer(from: candidate) {
                return formattedStockTypeLabel(container, count: stockLabelCount)
            }
        }
        for candidate in candidates {
            if let unit = extractPackageUnit(from: candidate) {
                return formattedStockTypeLabel(unit, count: stockLabelCount)
            }
        }
        return nil
    }

    private var stockUnitLabel: String {
        guard let pkg = primaryPackage else { return "unità" }
        let candidates = [
            pkg.tipologia,
            pkg.unita,
            packageDescriptor
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        for candidate in candidates {
            if let token = extractPackageUnit(from: candidate) {
                return token
            }
        }
        if let fallback = candidates.first {
            return fallback.lowercased()
        }
        return "unità"
    }

    private var stockLabelCount: Int {
        if let units = remainingUnits {
            return max(0, units)
        }
        return max(0, medicine.totalLeftover)
    }

    private func formattedStockTypeLabel(_ token: String, count: Int) -> String {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let inflected = inflectedPackageToken(normalized, count: count)
        return camelCase(inflected)
    }

    private func inflectedPackageToken(_ token: String, count: Int) -> String {
        let singularMap: [String: String] = [
            "compressa": "compressa",
            "compresse": "compressa",
            "capsula": "capsula",
            "capsule": "capsula",
            "fiala": "fiala",
            "fiale": "fiala",
            "ampolla": "ampolla",
            "ampolle": "ampolla",
            "siringa": "siringa",
            "siringhe": "siringa",
            "bustina": "bustina",
            "bustine": "bustina",
            "flacone": "flacone",
            "flaconi": "flacone",
            "flaconcino": "flaconcino",
            "flaconcini": "flaconcino",
            "cartuccia": "cartuccia",
            "cartucce": "cartuccia",
            "tubo": "tubo",
            "tubi": "tubo",
            "cerotto": "cerotto",
            "cerotti": "cerotto",
            "goccia": "goccia",
            "gocce": "goccia",
            "pezzo": "pezzo",
            "pezzi": "pezzo",
            "blister": "blister",
            "spray": "spray",
            "sciroppo": "sciroppo",
            "unità": "unità",
            "pz": "pz",
            "stick": "stick",
            "sachet": "sachet"
        ]
        let pluralMap: [String: String] = [
            "compressa": "compresse",
            "compresse": "compresse",
            "capsula": "capsule",
            "capsule": "capsule",
            "fiala": "fiale",
            "fiale": "fiale",
            "ampolla": "ampolle",
            "ampolle": "ampolle",
            "siringa": "siringhe",
            "siringhe": "siringhe",
            "bustina": "bustine",
            "bustine": "bustine",
            "flacone": "flaconi",
            "flaconi": "flaconi",
            "flaconcino": "flaconcini",
            "flaconcini": "flaconcini",
            "cartuccia": "cartucce",
            "cartucce": "cartucce",
            "tubo": "tubi",
            "tubi": "tubi",
            "cerotto": "cerotti",
            "cerotti": "cerotti",
            "goccia": "gocce",
            "gocce": "gocce",
            "pezzo": "pezzi",
            "pezzi": "pezzi",
            "blister": "blister",
            "spray": "spray",
            "sciroppo": "sciroppo",
            "unità": "unità",
            "pz": "pz",
            "stick": "stick",
            "sachet": "sachet"
        ]
        if count == 1 {
            return singularMap[token] ?? token
        }
        return pluralMap[token] ?? token
    }

    private func extractPackageUnit(from text: String) -> String? {
        let lowered = text.lowercased()
        let tokens = [
            "compresse", "compressa",
            "capsule", "capsula",
            "fiale", "fiala",
            "sciroppo",
            "spray",
            "gocce", "goccia",
            "cerotti", "cerotto",
            "bustine", "bustina",
            "siringhe", "siringa",
            "flaconi", "flacone",
            "ampolle", "ampolla",
            "cartucce", "cartuccia",
            "pz", "pezzi",
            "unità"
        ]
        for token in tokens where lowered.contains(token) {
            return token
        }
        return nil
    }

    private func extractPackageContainer(from text: String) -> String? {
        let lowered = text.lowercased()
        let tokens = [
            "blister",
            "cartuccia", "cartucce",
            "flacone", "flaconi",
            "flaconcino", "flaconcini",
            "boccetta", "boccette",
            "fiala", "fiale",
            "ampolla", "ampolle",
            "siringa", "siringhe",
            "bustina", "bustine",
            "tubo", "tubi",
            "stick",
            "sachet"
        ]
        for token in tokens where lowered.contains(token) {
            return token
        }
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
