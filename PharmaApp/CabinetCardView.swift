import SwiftUI
import CoreData

struct CabinetCardView: View {
    let cabinet: Cabinet
    var medicineCount: Int
    
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    
    var body: some View {
        let subtitle = makeDrawerSubtitle(drawer: cabinet, now: Date())
        HStack(alignment: .top, spacing: 12) {
            leadingIcon
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(cabinet.name)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text("\(medicineCount)")
                            .font(.system(size: 16, weight: .regular))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .regular))
                            .padding(.leading)
                    }
                    .foregroundStyle(Color.primary.opacity(0.45))
                }
                Text(subtitle.line1)
                    .font(.system(size: 14))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle.line2)
                    .font(.system(size: 14))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .background(Color.clear)
    }
    
    private var leadingIcon: some View {
        Image(systemName: "cross.case")
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(baseAccentColor)
            .frame(width: 18, height: 18, alignment: .center)
    }
    
    private var subtitleColor: Color {
        Color.primary.opacity(0.45)
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
        if medicines.isEmpty {
            return .gray
        }
        switch stockState {
        case .empty:
            return .red
        case .low:
            return .orange
        case .ok:
            return therapiesInCabinet.isEmpty ? .green : .blue
        }
    }
    
    private func evaluateStock(for medicine: Medicine) -> StockEvaluation? {
        let option = options.first
        if let therapies = medicine.therapies, !therapies.isEmpty {
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
            if days < medicine.stockThreshold(option: option) {
                return StockEvaluation(level: .low, coverageDays: max(0, days))
            }
            return StockEvaluation(level: .ok, coverageDays: max(0, days))
        }
        
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            if remaining <= 0 {
                return StockEvaluation(level: .empty, coverageDays: nil)
            } else if remaining < 5 {
                return StockEvaluation(level: .low, coverageDays: nil)
            } else {
                return StockEvaluation(level: .ok, coverageDays: nil)
            }
        }
        return nil
    }

    private var stockState: StockLevel {
        let evaluations = medicines.compactMap { evaluateStock(for: $0) }
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
        
        for medicine in medicinesWithTherapy {
            let schedule = scheduleToday(for: medicine)
            let taken = intakeLogsToday(for: medicine)
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
        
        for medicine in medicinesWithTherapy {
            let schedule = scheduleToday(for: medicine)
            let taken = intakeLogsToday(for: medicine)
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
    private var medicines: [Medicine] {
        Array(cabinet.medicines)
    }
    
    private var medicinesWithTherapy: [Medicine] {
        medicines.filter { $0.therapies?.isEmpty == false }
    }
    
    private var therapiesInCabinet: [Therapy] {
        medicinesWithTherapy.flatMap { Array($0.therapies ?? []) }
    }

    private var firstEmptyMedicine: Medicine? {
        medicines.first { evaluateStock(for: $0)?.level == .empty }
    }

    private var firstLowMedicine: Medicine? {
        medicines.first { evaluateStock(for: $0)?.level == .low }
    }

    private func lowestCoverageMedicine() -> (medicine: Medicine, evaluation: StockEvaluation, days: Int)? {
        var result: (Medicine, StockEvaluation, Int)?
        for med in medicines {
            guard let eval = evaluateStock(for: med), let days = eval.coverageDays else { continue }
            if let current = result {
                if days < current.2 {
                    result = (med, eval, days)
                }
            } else {
                result = (med, eval, days)
            }
        }
        return result
    }

    private func formattedName(_ medicine: Medicine) -> String {
        let raw = medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Medicinale" : raw
    }
    
    private func scheduleToday(for medicine: Medicine) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return [] }
        var times: [Date] = []
        for therapy in therapies {
            guard occursToday(therapy) else { continue }
            if let doseSet = therapy.doses as? Set<Dose> {
                for dose in doseSet {
                    let time = dose.time
                    if let combined = combine(day: today, withTime: time) {
                        times.append(combined)
                    }
                }
            }
        }
        return times.sorted()
    }
    
    private func intakeLogsToday(for medicine: Medicine) -> Int {
        let cal = Calendar.current
        let today = Date()
        guard let logs = medicine.logs else { return 0 }
        return logs.filter { $0.type == "intake" && cal.isDate($0.timestamp, inSameDayAs: today) }.count
    }
    
    private func occursToday(_ therapy: Therapy) -> Bool {
        let now = Date()
        let cal = Calendar.current
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? now
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
    
    private func icsCode(for date: Date) -> String {
        let wd = Calendar.current.component(.weekday, from: date)
        switch wd {
        case 1: return "SU"
        case 2: return "MO"
        case 3: return "TU"
        case 4: return "WE"
        case 5: return "TH"
        case 6: return "FR"
        case 7: return "SA"
        default: return "MO"
        }
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
