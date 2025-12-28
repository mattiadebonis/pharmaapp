import SwiftUI
import CoreData

// Modelli e builder per i todo di "Oggi" (estratti dall'ex TodayTodoView).

struct TodayTodoItem: Identifiable, Hashable {
    enum Category: String, CaseIterable, Hashable {
        case therapy
        case purchase
        case prescription
        case upcoming
        case pharmacy

        var label: String {
            switch self {
            case .therapy: return "Terapie di oggi"
            case .purchase: return "Acquisti"
            case .prescription: return "Ricette"
            case .upcoming: return "Prossimi giorni"
            case .pharmacy: return "Farmacia"
            }
        }

        var icon: String {
            switch self {
            case .therapy: return "pills.circle"
            case .purchase: return "cart.badge.plus"
            case .prescription: return "doc.text.magnifyingglass"
            case .upcoming: return "calendar"
            case .pharmacy: return "mappin.and.ellipse"
            }
        }

        var tint: Color {
            switch self {
            case .therapy: return .blue
            case .purchase: return .green
            case .prescription: return .orange
            case .upcoming: return .purple
            case .pharmacy: return .teal
            }
        }

        static var displayOrder: [Category] {
            [.therapy, .purchase, .prescription, .upcoming, .pharmacy]
        }
    }

    let id: String
    let title: String
    let detail: String?
    let category: Category
    let medicineID: NSManagedObjectID?
}

enum TodayTodoBuilder {
    static func makeTodos(from context: AIInsightsContext, medicines: [Medicine], urgentIDs: Set<NSManagedObjectID>) -> [TodayTodoItem] {
        var items: [TodayTodoItem] = []
        let medIndex: [String: Medicine] = {
            var dict: [String: Medicine] = [:]
            for med in medicines {
                dict[med.nome.lowercased()] = med
            }
            return dict
        }()

        for highlight in context.therapyHighlights {
            guard let parsed = parseHighlight(highlight) else { continue }
            let detailRaw = parsed.detail.flatMap { normalizedTimeDetail(from: $0) } ?? parsed.detail
            let salt = medIndex[parsed.name.lowercased()]?.latestLogSalt ?? ""
            items.append(
                TodayTodoItem(
                    id: "therapy|\(parsed.id)|\(salt)",
                    title: parsed.name,
                    detail: detailRaw,
                    category: .therapy,
                    medicineID: medIndex[parsed.name.lowercased()]?.objectID
                )
            )
        }

        for highlight in context.purchaseHighlights {
            guard let parsed = parsePurchaseHighlight(highlight) else { continue }
            let medID = medIndex[parsed.name.lowercased()]?.objectID
            let salt = medIndex[parsed.name.lowercased()]?.latestLogSalt ?? ""
            let detailWithUrgency = detailForAction(base: parsed.detail, medicine: medIndex[parsed.name.lowercased()], urgentIDs: urgentIDs)
            items.append(
                TodayTodoItem(
                    id: "purchase|\(parsed.name.lowercased())|\(parsed.status.rawValue)|\(salt)",
                    title: parsed.name,
                    detail: detailWithUrgency,
                    category: .purchase,
                    medicineID: medID
                )
            )
        }

        for highlight in context.prescriptionHighlights {
            guard let parsed = parseHighlight(highlight) else { continue }
            let medID = medIndex[parsed.name.lowercased()]?.objectID
            let med = medIndex[parsed.name.lowercased()]
            let salt = med?.latestLogSalt ?? ""
            let baseDetail: String?
            if let med, med.hasNewPrescritpionRequest() {
                baseDetail = parsed.detail
            } else {
                baseDetail = nil
            }
            let detailWithUrgency = detailForAction(base: baseDetail, medicine: med, urgentIDs: urgentIDs)
            items.append(
                TodayTodoItem(
                    id: "prescription|\(parsed.id)|\(salt)",
                    title: parsed.name,
                    detail: detailWithUrgency,
                    category: .prescription,
                    medicineID: medID
                )
            )
        }

        return items
    }

    private static func parseHighlight(_ highlight: String) -> (id: String, name: String, detail: String?)? {
        let components = highlight.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let name = components.first, !name.isEmpty else { return nil }
        let detail = components.count > 1 ? components[1] : nil
        let identifier = "\(name.lowercased())|\(detail?.lowercased() ?? "")"
        return (identifier, name, detail)
    }

    private enum PurchaseStatus: String {
        case waitingRx
        case normal
    }

    private static func parsePurchaseHighlight(_ highlight: String) -> (id: String, name: String, detail: String?, status: PurchaseStatus)? {
        let trimmed = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let raw = components.first, !raw.isEmpty else { return nil }
        var detail = components.count > 1 ? components[1] : nil
        let lower = raw.lowercased()
        let name: String
        if lower.hasPrefix("compra ") {
            name = raw.dropFirst("compra ".count).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let status: PurchaseStatus = (raw.contains("attesa della ricetta") || trimmed.lowercased().contains("ricetta")) ? .waitingRx : .normal
        if status == .waitingRx && (detail == nil || detail?.isEmpty == true) {
            detail = "In attesa della ricetta"
        }
        let identifier = "\(name.lowercased())|\(status.rawValue)"
        return (identifier, name, detail, status)
    }

    private static func detailForAction(base: String?, medicine: Medicine?, urgentIDs: Set<NSManagedObjectID>) -> String? {
        var parts: [String] = []
        if let base, !base.isEmpty {
            parts.append(base)
        }
        if let med = medicine, !urgentIDs.contains(med.objectID), let dose = nextDoseTodayText(for: med) {
            parts.append("Oggi: \(dose)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func nextDoseTodayText(for medicine: Medicine) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let now = Date()
        let calendar = Calendar.current
        let upcoming = therapies.compactMap { therapy -> Date? in
            guard let next = nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: rec) else {
                return nil
            }
            return calendar.isDateInToday(next) ? next : nil
        }.sorted().first
        guard let next = upcoming else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: next)
    }

    private static func combine(day: Date, withTime time: Date) -> Date? {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)

        var mergedComponents = DateComponents()
        mergedComponents.year = dayComponents.year
        mergedComponents.month = dayComponents.month
        mergedComponents.day = dayComponents.day
        mergedComponents.hour = timeComponents.hour
        mergedComponents.minute = timeComponents.minute
        mergedComponents.second = timeComponents.second

        return calendar.date(from: mergedComponents)
    }

    private static func icsCode(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
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

    private static func occursToday(_ therapy: Therapy, now: Date, recurrenceManager: RecurrenceManager) -> Bool {
        let calendar = Calendar.current
        let endOfDay: Date = {
            let start = calendar.startOfDay(for: now)
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
        }()
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? now

        if start > endOfDay { return false }
        if let until = rule.until, calendar.startOfDay(for: until) < calendar.startOfDay(for: now) { return false }

        let freq = rule.freq.uppercased()
        let interval = rule.interval ?? 1

        switch freq {
        case "DAILY":
            let startSOD = calendar.startOfDay(for: start)
            let todaySOD = calendar.startOfDay(for: now)
            if let days = calendar.dateComponents([.day], from: startSOD, to: todaySOD).day, days >= 0 {
                return days % max(1, interval) == 0
            }
            return false

        case "WEEKLY":
            let todayCode = icsCode(for: now, calendar: calendar)
            let byDays = rule.byDay.isEmpty ? ["MO", "TU", "WE", "TH", "FR", "SA", "SU"] : rule.byDay
            guard byDays.contains(todayCode) else { return false }

            let startWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
            let todayWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            if let weeks = calendar.dateComponents([.weekOfYear], from: startWeek, to: todayWeek).weekOfYear, weeks >= 0 {
                return weeks % max(1, interval) == 0
            }
            return false

        default:
            return false
        }
    }

    private static func scheduledTimesToday(for therapy: Therapy, now: Date, recurrenceManager: RecurrenceManager) -> [Date] {
        guard occursToday(therapy, now: now, recurrenceManager: recurrenceManager) else { return [] }
        guard let doseSet = therapy.doses, !doseSet.isEmpty else { return [] }
        let today = Calendar.current.startOfDay(for: now)
        return doseSet.compactMap { dose in
            combine(day: today, withTime: dose.time)
        }.sorted()
    }

    private static func intakeCountToday(for therapy: Therapy, medicine: Medicine, now: Date) -> Int {
        let calendar = Calendar.current
        let logsToday = (medicine.logs ?? []).filter { $0.type == "intake" && calendar.isDate($0.timestamp, inSameDayAs: now) }
        let assigned = logsToday.filter { $0.therapy == therapy }.count
        if assigned > 0 { return assigned }

        let unassigned = logsToday.filter { $0.therapy == nil }
        let therapyCount = medicine.therapies?.count ?? 0
        if therapyCount == 1 { return unassigned.count }
        return unassigned.filter { $0.package == therapy.package }.count
    }

    private static func nextUpcomingDoseDate(for therapy: Therapy, medicine: Medicine, now: Date, recurrenceManager: RecurrenceManager) -> Date? {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let startDate = therapy.start_date ?? now
        let calendar = Calendar.current

        let timesToday = scheduledTimesToday(for: therapy, now: now, recurrenceManager: recurrenceManager)
        if calendar.isDateInToday(now), !timesToday.isEmpty {
            let takenCount = intakeCountToday(for: therapy, medicine: medicine, now: now)
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

    private static func normalizedTimeDetail(from detail: String) -> String? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[0-9]{1,2}:[0-9]{2}$"
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return "alle \(trimmed)"
        }
        return nil
    }
}

private extension Medicine {
    var latestLogSalt: String {
        guard let logs = logs, let lastDate = logs.map(\.timestamp).max() else { return "0" }
        return String(Int(lastDate.timeIntervalSince1970))
    }
}
