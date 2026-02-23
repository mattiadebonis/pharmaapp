import SwiftUI
import CoreData

enum MedicineSubtitleMode {
    case nextDose
    case activeTherapies
}

struct MedicineRowView: View {
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    private let recurrenceManager = RecurrenceManager.shared
    
    // MARK: - Costanti
    // MARK: - Input
    @ObservedObject var medicine: Medicine
    var medicinePackage: MedicinePackage? = nil
    var subtitleMode: MedicineSubtitleMode = .nextDose
    var isSelected: Bool = false
    var isInSelectionMode: Bool = false
    enum RowSection { case purchase, tuttoOk }
    
    // MARK: - Computed
    private var option: Option? { options.first }
    private var therapies: Set<Therapy> {
        guard let entry = medicinePackage else {
            return medicine.therapies as? Set<Therapy> ?? []
        }
        if let entryTherapies = entry.therapies, !entryTherapies.isEmpty {
            return entryTherapies
        }
        let all = medicine.therapies as? Set<Therapy> ?? []
        return Set(all.filter { $0.package == entry.package })
    }
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
    private func allowedEvents(on day: Date, for therapy: Therapy) -> Int {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? day
        let perDay = max(1, therapy.doses?.count ?? 0)
        return recurrenceManager.allowedEvents(on: day, rule: rule, startDate: start, dosesPerDay: perDay)
    }

    private func occursToday(_ t: Therapy) -> Bool {
        let now = Date()
        return allowedEvents(on: now, for: t) > 0
    }
    // MARK: - New computed helpers for UI
    private var nextDate: Date? { nextOcc?.date }
    // Dosi odierne pianificate vs assunte
    private var scheduledDosesToday: Int {
        guard !therapies.isEmpty else { return 0 }
        let now = Date()
        return therapies.reduce(0) { acc, t in
            acc + allowedEvents(on: now, for: t)
        }
    }
    private var intakeLogsToday: Int {
        let now = Date()
        let cal = Calendar.current
        let filtered = medicine.effectiveIntakeLogs(on: now, calendar: cal)
        guard let entry = medicinePackage else { return filtered.count }
        return filtered.filter { $0.package == entry.package }.count
    }
    private var scheduledTimesToday: [Date] {
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard !therapies.isEmpty else { return [] }
        var times: [Date] = []
        for t in therapies {
            let allowed = allowedEvents(on: today, for: t)
            guard allowed > 0 else { continue }
            if let doseSet = t.doses as? Set<Dose> {
                let sortedDoses = doseSet.sorted { $0.time < $1.time }
                let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
                for d in limitedDoses {
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
        if let entry = medicinePackage {
            let context = medicine.managedObjectContext ?? entry.package.managedObjectContext ?? PersistenceController.shared.container.viewContext
            return StockService(context: context).units(for: entry.package)
        }
        return medicine.remainingUnitsWithoutTherapy()
    }
    private var primaryPackageLabel: String? {
        guard let pkg = primaryPackage else { return nil }
        if let desc = packageDescriptionLabel(pkg) {
            return desc
        }
        return packageQuantityLabel(pkg)
    }
    // MARK: - Body
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                titleLine
                subtitleBlock
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .overlay {
            if isInSelectionMode {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selectionBorderColor, lineWidth: selectionBorderWidth)
            }
        }
    }
    
    private struct MedicineRowPresentationSnapshot {
        let line1: String
        let line2: String
        let therapyLines: [TherapyLine]
        let deadlineIndicator: (symbol: String, color: Color, label: String)?
        let stockWarning: (text: String, color: Color, icon: String)?
    }

    private var presentationSnapshot: MedicineRowPresentationSnapshot {
        let now = Date()
        switch subtitleMode {
        case .activeTherapies:
            let intakeLogsToday = intakeLogsTodayRecords(on: now)
            let payload = makeMedicineActiveTherapiesSubtitle(
                medicine: medicine,
                medicinePackage: medicinePackage,
                recurrenceManager: recurrenceManager,
                intakeLogsToday: intakeLogsToday,
                now: now
            )
            return MedicineRowPresentationSnapshot(
                line1: payload.line1,
                line2: payload.line2,
                therapyLines: payload.therapyLines,
                deadlineIndicator: deadlineIndicator,
                stockWarning: nil
            )
        case .nextDose:
            let subtitle = makeMedicineSubtitle(
                medicine: medicine,
                medicinePackage: medicinePackage,
                now: now
            )
            return MedicineRowPresentationSnapshot(
                line1: subtitle.line1,
                line2: subtitle.line2,
                therapyLines: [],
                deadlineIndicator: deadlineIndicator,
                stockWarning: stocksWarning
            )
        }
    }

    private func intakeLogsTodayRecords(on now: Date) -> [Log] {
        let calendar = Calendar.current
        let logsToday = medicine.effectiveIntakeLogs(on: now, calendar: calendar)
        guard let entry = medicinePackage else { return logsToday }
        return logsToday.filter { $0.package == entry.package }
    }

    private var subtitleBlock: some View {
        let snapshot = presentationSnapshot
        return VStack(alignment: .leading, spacing: subtitleBlockSpacing) {
            if !snapshot.line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(snapshot.line1)
                    .font(subtitleFont)
                    .foregroundColor(line1Color)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
            }
            if subtitleMode == .activeTherapies {
                therapyLinesView(snapshot.therapyLines)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    line2View(for: snapshot.line2)
                }
            }
            if let indicator = snapshot.deadlineIndicator {
                Text(indicator.label)
                    .font(subtitleFont)
                    .foregroundColor(indicator.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private func line2View(for line: String) -> some View {
        Text(line)
            .font(subtitleFont)
            .foregroundColor(line2Color)
            .lineLimit(subtitleMode == .activeTherapies ? nil : 1)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
    }

    private var subtitleColor: Color {
        Color.primary.opacity(0.45)
    }

    private var subtitleFont: Font {
        .system(size: 15, weight: .regular)
    }

    @ViewBuilder
    private func therapyLinesView(_ lines: [TherapyLine]) -> some View {
        if lines.isEmpty {
            Text("Nessuna terapia attiva")
                .font(subtitleFont)
                .foregroundColor(subtitleColor)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            VStack(alignment: .leading, spacing: subtitleBlockSpacing) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    therapyLineText(line)
                        .font(subtitleFont)
                        .foregroundColor(therapyLineColor)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var isAutonomyBelowThreshold: Bool {
        if !therapies.isEmpty {
            guard let days = autonomyDays else { return false }
            return days < coverageThreshold
        }
        guard let units = remainingUnits else { return false }
        return units < coverageThreshold
    }

    private var hasSkippedDose: Bool {
        earliestOverdueDoseTime != nil
    }

    private var line1Color: Color {
        switch subtitleMode {
        case .activeTherapies:
            return isAutonomyBelowThreshold ? .red : subtitleColor
        case .nextDose:
            return hasSkippedDose ? .red : subtitleColor
        }
    }

    private var line2Color: Color {
        switch subtitleMode {
        case .activeTherapies:
            return subtitleColor
        case .nextDose:
            return isAutonomyBelowThreshold ? .red : subtitleColor
        }
    }

    private var therapyLineColor: Color {
        hasSkippedDose ? .red : subtitleColor
    }

    private func therapyLineText(_ line: TherapyLine) -> Text {
        if let prefix = line.prefix, !prefix.isEmpty {
            return Text(prefix)
                + Text(" ")
                + Text(Image(systemName: "repeat"))
                + Text(" ")
                + Text(line.description)
        }
        return Text(line.description)
    }

    private var subtitleBlockSpacing: CGFloat {
        subtitleMode == .activeTherapies ? 3 : 1
    }

    private var deadlineIndicator: (symbol: String, color: Color, label: String)? {
        switch medicine.deadlineStatus {
        case .expired:
            return ("alarm.fill", .red, "Scaduto")
        case .expiringSoon:
            return ("alarm", .orange, "Scadenza vicina")
        case .ok, .none:
            return nil
        }
    }

    private var titleLine: some View {
        let trimmed = medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Medicinale" : trimmed
        let name = camelCase(base)
        let dosage = primaryPackageDosage
        return HStack(alignment: .bottom, spacing: 4) {
            Text(name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(2)
            if let dosage {
                Text(" \(dosage)")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var firstPackageInfo: String? {
        guard let pkg = primaryPackage else { return nil }
        return packageDescriptionLabel(pkg)
    }

    private var primaryPackage: Package? {
        if let entry = medicinePackage {
            return entry.package
        }
        return medicine.packages.sorted { $0.numero > $1.numero }.first
    }

    private var primaryPackageDosage: String? {
        guard let pkg = primaryPackage else { return nil }
        return packageDosageLabel(pkg)
    }

    private func packageQuantityLabel(_ pkg: Package) -> String? {
        let typeRaw = pkg.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
        if pkg.numero > 0 {
            let unitLabel = typeRaw.isEmpty ? "unità" : typeRaw.lowercased()
            return "\(pkg.numero) \(unitLabel)"
        }
        return typeRaw.isEmpty ? nil : typeRaw.capitalized
    }

    private func packageDosageLabel(_ pkg: Package) -> String? {
        guard pkg.valore > 0 else { return nil }
        let unit = pkg.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? "\(pkg.valore)" : "\(pkg.valore) \(unit)"
    }

    private func packageDescriptionLabel(_ pkg: Package) -> String? {
        let qty = pkg.numero > 0 ? "\(pkg.numero)" : nil
        let formRaw = pkg.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = formRaw.split(separator: "-").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        func isDosage(_ token: String) -> Bool {
            let lower = token.lowercased()
            if lower.range(of: "\\d", options: .regularExpression) == nil { return false }
            return lower.contains("mg") || lower.contains("mcg") || lower.contains("g") || lower.contains("ml")
        }

        func isRouteToken(_ token: String) -> Bool {
            let lower = token.lowercased()
            return lower.contains("uso") || lower.contains("orale") || lower.contains("nasale") || lower.contains("cutaneo") || lower.contains("sublinguale")
        }

        func isContainer(_ token: String) -> Bool {
            let lower = token.lowercased()
            return lower.contains("blister") || lower.contains("flacone") || lower.contains("flaconcino") || lower.contains("siringa")
        }

        let form = tokens.first(where: { !isDosage($0) && !isRouteToken($0) && !isContainer($0) })?.lowercased()
            ?? (formRaw.isEmpty ? nil : formRaw.lowercased())
        let route = (tokens.first(where: isRouteToken) ?? usageRoute(for: form))?.lowercased()

        var parts: [String] = []
        if let form {
            parts.append(form.lowercased())
        }

        if let route = route {
            parts.append(route)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func usageRoute(for form: String?) -> String? {
        // Non abbiamo un campo dedicato: usiamo un testo generico, ma solo se la forma è nota
        guard form != nil else { return nil }
        return "per uso orale"
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
        let logsToday = medicine.effectiveIntakeLogs(on: now, calendar: calendar)
        let assigned = logsToday.filter { $0.therapy == therapy }.count
        if assigned > 0 { return assigned }

        let unassigned = logsToday.filter { $0.therapy == nil }
        if therapies.count == 1 { return unassigned.count }
        return unassigned.filter { $0.package == therapy.package }.count
    }

    private func scheduledTimesToday(for therapy: Therapy, now: Date) -> [Date] {
        let today = Calendar.current.startOfDay(for: now)
        let allowed = allowedEvents(on: today, for: therapy)
        guard allowed > 0 else { return [] }
        guard let doseSet = therapy.doses as? Set<Dose>, !doseSet.isEmpty else { return [] }
        let sortedDoses = doseSet.sorted { $0.time < $1.time }
        let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
        return limitedDoses.compactMap { dose in
            combine(day: today, withTime: dose.time)
        }
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
        if first.lowercased() == "persona" { return nil }
        return first.isEmpty ? nil : first
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
        if first.lowercased() == "persona" { return nil }
        return first.isEmpty ? nil : first
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
            if let unit = extractPackageUnit(from: candidate) {
                return formattedStockTypeLabel(unit, count: stockLabelCount)
            }
        }
        for candidate in candidates {
            if let container = extractPackageContainer(from: candidate) {
                return formattedStockTypeLabel(container, count: stockLabelCount)
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
