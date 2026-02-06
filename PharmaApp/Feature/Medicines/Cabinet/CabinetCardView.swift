import SwiftUI
import CoreData

struct CabinetCardView: View {
    let cabinet: Cabinet

    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)

    static let textIndent: CGFloat = Layout.leadingIconWidth + Layout.leadingSpacing

    private enum Layout {
        static let leadingIconWidth: CGFloat = 24
        static let leadingSpacing: CGFloat = 18
    }
    
    var body: some View {
        let subtitle = makeDrawerSubtitle(drawer: cabinet, now: Date())
        HStack(alignment: .top, spacing: Layout.leadingSpacing) {
            leadingIcon
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cabinet.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        Text("\(therapyCount)")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
                if let subtitle {
                    Text(subtitle.line1)
                        .font(condensedSubtitleFont)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(subtitle.therapyLines.enumerated()), id: \.offset) { _, line in
                            therapyLineText(line)
                                .font(condensedSubtitleFont)
                                .foregroundStyle(subtitleColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .background(Color.clear)
    }
    
    private var leadingIcon: some View {
        Image(systemName: "cross.case.fill")
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(baseAccentColor)
            .frame(width: Layout.leadingIconWidth, height: Layout.leadingIconWidth, alignment: .center)
    }
    
    private var subtitleColor: Color {
        Color.primary.opacity(0.45)
    }

    private var condensedSubtitleFont: Font {
        Font.custom("SFProDisplay-CondensedLight", size: 15)
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
    
    // MARK: - Stock summary
    private enum StockLevel {
        case empty
        case low
        case ok
    }
    
    private struct StockEvaluation {
        let level: StockLevel
        let coverageDays: Int?
    }
    
    
    private var baseAccentColor: Color {
        .accentColor
    }

    private var therapyCount: Int {
        let unique = Set(therapiesInCabinet.map(\.objectID))
        return unique.count
    }
    
    private func evaluateStock(for entry: MedicinePackage) -> StockEvaluation? {
        let option = options.first
        let therapies = therapies(for: entry)
        if !therapies.isEmpty {
            var totalLeftover: Double = 0
            var dailyUsage: Double = 0
            for therapy in therapies {
                totalLeftover += Double(therapy.leftover())
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            guard dailyUsage > 0 else { return nil }
            if totalLeftover <= 0 {
                return StockEvaluation(level: .empty, coverageDays: 0)
            }
            let days = Int(floor(totalLeftover / dailyUsage))
            if days < entry.medicine.stockThreshold(option: option) {
                return StockEvaluation(level: .low, coverageDays: max(0, days))
            }
            return StockEvaluation(level: .ok, coverageDays: max(0, days))
        }
        let remaining = StockService(context: PersistenceController.shared.container.viewContext).units(for: entry.package)
        if remaining <= 0 {
            return StockEvaluation(level: .empty, coverageDays: nil)
        } else if remaining < 5 {
            return StockEvaluation(level: .low, coverageDays: nil)
        } else {
            return StockEvaluation(level: .ok, coverageDays: nil)
        }
        return nil
    }

    private var stockState: StockLevel {
        let evaluations = entries.compactMap { evaluateStock(for: $0) }
        if evaluations.contains(where: { $0.level == .empty }) {
            return .empty
        }
        if evaluations.contains(where: { $0.level == .low }) {
            return .low
        }
        return .ok
    }
    
    private var overdueInfo: (count: Int, earliest: Date?) {
        let now = Date()
        var totalOverdue = 0
        var earliestOverdue: Date?
        
        for entry in entriesWithTherapy {
            let schedule = scheduleToday(for: entry)
            let taken = intakeLogsToday(for: entry)
            let pending = Array(schedule.dropFirst(min(taken, schedule.count)))
            let overdue = pending.filter { $0 <= now }
            totalOverdue += overdue.count
            if let first = overdue.min() {
                earliestOverdue = minDate(earliestOverdue, first)
            }
        }
        return (totalOverdue, earliestOverdue)
    }
    
    private var todaySchedule: (pendingToday: Int, firstPending: Date?) {
        let now = Date()
        var totalPending = 0
        var firstPending: Date?
        
        for entry in entriesWithTherapy {
            let schedule = scheduleToday(for: entry)
            let taken = intakeLogsToday(for: entry)
            let pending = Array(schedule.dropFirst(min(taken, schedule.count)))
            totalPending += pending.count
            if let first = pending.filter({ $0 > now }).min() {
                firstPending = minDate(firstPending, first)
            }
        }
        return (totalPending, firstPending)
    }
    
    private var nextDoseDate: Date? {
        var nextDate: Date?
        for therapy in therapiesInCabinet {
            guard let start = therapy.start_date else { continue }
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            if let date = recurrenceManager.nextOccurrence(rule: rule, startDate: start, after: Date(), doses: therapy.doses as NSSet?) {
                nextDate = minDate(nextDate, date)
            }
        }
        return nextDate
    }
    
    // MARK: - Helpers
    private var entries: [MedicinePackage] {
        Array(cabinet.medicinePackages ?? [])
    }
    
    private var entriesWithTherapy: [MedicinePackage] {
        entries.filter { !therapies(for: $0).isEmpty }
    }
    
    private var therapiesInCabinet: [Therapy] {
        entriesWithTherapy.flatMap { therapies(for: $0) }
    }

    private var firstEmptyEntry: MedicinePackage? {
        entries.first { evaluateStock(for: $0)?.level == .empty }
    }

    private var firstLowEntry: MedicinePackage? {
        entries.first { evaluateStock(for: $0)?.level == .low }
    }

    private func lowestCoverageEntry() -> (entry: MedicinePackage, evaluation: StockEvaluation, days: Int)? {
        var result: (MedicinePackage, StockEvaluation, Int)?
        for entry in entries {
            guard let eval = evaluateStock(for: entry), let days = eval.coverageDays else { continue }
            if let current = result {
                if days < current.2 {
                    result = (entry, eval, days)
                }
            } else {
                result = (entry, eval, days)
            }
        }
        return result
    }

    private func formattedName(_ entry: MedicinePackage) -> String {
        let raw = entry.medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Medicinale" : raw
    }
    
    private func scheduleToday(for entry: MedicinePackage) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let therapies = therapies(for: entry)
        guard !therapies.isEmpty else { return [] }
        var times: [Date] = []
        for therapy in therapies {
            let allowed = allowedEvents(on: today, for: therapy)
            guard allowed > 0 else { continue }
            if let doseSet = therapy.doses as? Set<Dose> {
                let sortedDoses = doseSet.sorted { $0.time < $1.time }
                let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
                for dose in limitedDoses {
                    let time = dose.time
                    if let combined = combine(day: today, withTime: time) {
                        times.append(combined)
                    }
                }
            }
        }
        return times.sorted()
    }
    
    private func intakeLogsToday(for entry: MedicinePackage) -> Int {
        let cal = Calendar.current
        let today = Date()
        let logs = entry.medicine.effectiveIntakeLogs(on: today, calendar: cal)
        return logs.filter { $0.package == entry.package }.count
    }

    private func therapies(for entry: MedicinePackage) -> [Therapy] {
        if let set = entry.therapies, !set.isEmpty {
            return Array(set)
        }
        let all = entry.medicine.therapies as? Set<Therapy> ?? []
        return all.filter { $0.package == entry.package }
    }
    
    private func allowedEvents(on day: Date, for therapy: Therapy) -> Int {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? day
        let perDay = max(1, therapy.doses?.count ?? 0)
        return recurrenceManager.allowedEvents(on: day, rule: rule, startDate: start, dosesPerDay: perDay)
    }

    private func occursToday(_ therapy: Therapy) -> Bool {
        let now = Date()
        return allowedEvents(on: now, for: therapy) > 0
    }
    
    private func combine(day: Date, withTime time: Date) -> Date? {
        let cal = Calendar.current
        var comps = DateComponents()
        let dayComps = cal.dateComponents([.year, .month, .day], from: day)
        let timeComps = cal.dateComponents([.hour, .minute, .second], from: time)
        comps.year = dayComps.year
        comps.month = dayComps.month
        comps.day = dayComps.day
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second
        return cal.date(from: comps)
    }
    
    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
    
    private func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
    
    private func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?): return min(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }
}
