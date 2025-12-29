import SwiftUI
import CoreData

/// ViewModel dedicato al tab "Oggi".
/// Sposta la logica di costruzione dei todo e degli insight fuori dalla view.
class TodayViewModel: ObservableObject {
    struct TimeGroup: Identifiable {
        let id = UUID()
        let label: String
        let sortValue: Int?
        let items: [TodayTodoItem]
    }

    let actionService: MedicineActionService

    init(actionService: MedicineActionService = MedicineActionService()) {
        self.actionService = actionService
    }

    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    // MARK: - Insights / Todo building
    func buildInsightsContext(
        for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]),
        medicines: [Medicine],
        option: Option?
    ) -> AIInsightsContext? {
        let rec = RecurrenceManager(context: viewContext)
        let purchaseLines = sections.purchase.map { medicine in
            "\(medicine.nome): \(purchaseHighlight(for: medicine, option: option, recurrenceManager: rec))"
        }
        let therapySources = sections.oggi + sections.purchase
        let therapyLines = therapySources.compactMap { medicine in
            nextDoseTodayHighlight(for: medicine, recurrenceManager: rec)
        }
        let upcomingLines = sections.ok.prefix(3).compactMap { medicine in
            nextDoseHighlight(for: medicine, recurrenceManager: rec)
        }
        var prescriptionLines: [String] = []
        for medicine in medicines {
            guard needsPrescriptionBeforePurchase(medicine, option: option, recurrenceManager: rec) else { continue }
            prescriptionLines.append(medicine.nome)
            if prescriptionLines.count >= 6 { break }
        }
        let context = AIInsightsContext(
            purchaseHighlights: purchaseLines,
            therapyHighlights: therapyLines,
            upcomingHighlights: upcomingLines,
            prescriptionHighlights: prescriptionLines,
            pharmacySuggestion: purchaseLines.isEmpty ? nil : nil
        )
        return context.hasSignals ? context : nil
    }

    func buildTodoItems(
        from context: AIInsightsContext?,
        medicines: [Medicine],
        urgentIDs: Set<NSManagedObjectID>,
        option: Option?
    ) -> [TodayTodoItem] {
        guard let context else { return [] }
        var items = TodayTodoBuilder.makeTodos(from: context, medicines: medicines, urgentIDs: urgentIDs)
        items = items.filter { [.therapy, .purchase, .prescription].contains($0.category) }
        let blockedMedicineIDs: Set<NSManagedObjectID> = Set(
            items.compactMap { item in
                guard let info = blockedTherapyInfo(for: item, medicines: medicines, option: option) else { return nil }
                return info.objectID
            }
        )
        let rec = RecurrenceManager(context: viewContext)
        if !blockedMedicineIDs.isEmpty {
            items = items.filter { item in
                guard let medID = item.medicineID else { return true }
                guard blockedMedicineIDs.contains(medID) else { return true }
                if item.category == .prescription { return false }
                return true
            }
        }
        // Se esiste un todo di acquisto per un medicinale, rimuovi il todo di ricetta duplicato:
        let purchaseIDs: Set<NSManagedObjectID> = Set(items.compactMap { item in
            item.category == .purchase ? item.medicineID : nil
        })
        if !purchaseIDs.isEmpty {
            items = items.filter { item in
                if item.category == .prescription, let medID = item.medicineID {
                    return !purchaseIDs.contains(medID)
                }
                return true
            }
        }
        items = items.map { item in
            if item.category == .prescription,
               let med = medicine(for: item, medicines: medicines),
               needsPrescriptionBeforePurchase(med, option: option, recurrenceManager: rec) {
                return TodayTodoItem(
                    id: "purchase|rx|\(item.id)",
                    title: item.title,
                    detail: item.detail,
                    category: .purchase,
                    medicineID: item.medicineID
                )
            }
            return item
        }
        // Evita di duplicare il farmaco sia nella sezione oraria (terapia) sia nei rifornimenti
        items = items.filter { item in
            if item.category == .purchase,
               let med = medicine(for: item, medicines: medicines),
               med.hasIntakeToday(recurrenceManager: rec),
               !med.hasIntakeLoggedToday(),
               isOutOfStock(med, option: option, recurrenceManager: rec) {
                return false
            }
            return true
        }
        return items
    }

    func sortTodos(_ items: [TodayTodoItem]) -> [TodayTodoItem] {
        items.sorted { lhs, rhs in
            let lTime = timeSortValue(for: lhs) ?? Int.max
            let rTime = timeSortValue(for: rhs) ?? Int.max
            if lTime != rTime { return lTime < rTime }
            if categoryRank(lhs.category) != categoryRank(rhs.category) {
                return categoryRank(lhs.category) < categoryRank(rhs.category)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func timeGroups(from items: [TodayTodoItem], medicines: [Medicine], options: Option?) -> [TimeGroup] {
        var grouped: [String: (sort: Int?, items: [TodayTodoItem])] = [:]
        for item in items {
            let label = timeLabel(for: item, medicines: medicines, options: options) ?? "Rifornimenti"
            let sortValue = timeSortValue(for: item)
            var current = grouped[label] ?? (sort: sortValue, items: [])
            current.items.append(item)
            if let sortValue {
                current.sort = min(current.sort ?? sortValue, sortValue)
            }
            grouped[label] = current
        }

        return grouped.map { TimeGroup(label: $0.key, sortValue: $0.value.sort, items: $0.value.items) }
            .sorted { lhs, rhs in
                if lhs.label == "Rifornimenti", rhs.label != "Rifornimenti" { return false }
                if rhs.label == "Rifornimenti", lhs.label != "Rifornimenti" { return true }
                switch (lhs.sortValue, rhs.sortValue) {
                case let (l?, r?):
                    return l < r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.label < rhs.label
                }
            }
    }

    func timeLabel(for item: TodayTodoItem, medicines: [Medicine], options: Option?) -> String? {
        if item.category == .purchase {
            return "Rifornimenti"
        }
        guard let date = todoTimeDate(for: item, medicines: medicines, options: options) else { return nil }
        return TodayFormatters.time.string(from: date)
    }

    func categoryRank(_ category: TodayTodoItem.Category) -> Int {
        TodayTodoItem.Category.displayOrder.firstIndex(of: category) ?? Int.max
    }

    func urgentMedicineIDs(for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> Set<NSManagedObjectID> {
        let rec = RecurrenceManager(context: viewContext)
        let allMedicines = sections.purchase + sections.oggi + sections.ok
        let urgent = allMedicines.filter {
            isOutOfStock($0, option: nil, recurrenceManager: rec) && hasUpcomingTherapyInNextWeek(for: $0, recurrenceManager: rec)
        }
        return Set(urgent.map { $0.objectID })
    }

    // MARK: - Helpers
    private func purchaseHighlight(for medicine: Medicine, option: Option?, recurrenceManager: RecurrenceManager) -> String {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalLeft <= 0 {
                if let nextToday = earliestDoseToday(for: medicine, recurrenceManager: recurrenceManager) {
                    let fmt = DateFormatter(); fmt.timeStyle = .short
                    return "scorte terminate · da prendere alle \(fmt.string(from: nextToday))"
                }
                return "scorte terminate"
            }
            guard totalDaily > 0 else {
                return "copertura non stimabile"
            }
            let days = Int(totalLeft / totalDaily)
            if days <= 0 { return "scorte terminate" }
            return days == 1 ? "copertura per 1 giorno" : "copertura per \(days) giorni"
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            if remaining <= 0 { return "nessuna unità residua" }
            if remaining < 5 { return "solo \(remaining) unità" }
            return "\(remaining) unità disponibili"
        }
        return "scorte non monitorate"
    }

    private func nextDoseHighlight(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let upcomingDates = therapies.compactMap { therapy in
            nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager)
        }
        guard let next = upcomingDates.sorted().first else { return nil }
        if calendar.isDateInToday(next) {
            return "\(medicine.nome): \(TodayFormatters.time.string(from: next))"
        } else if calendar.isDateInTomorrow(next) {
            return "\(medicine.nome): domani"
        }
        let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
        return "\(medicine.nome): \(fmt.string(from: next))"
    }

    private func nextDoseTodayHighlight(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var timesToday: [Date] = []
        for therapy in therapies {
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let startDate = therapy.start_date ?? now
            let next = recurrenceManager.nextOccurrence(rule: rule, startDate: startDate, after: today, doses: therapy.doses as NSSet?)
            if let next, calendar.isDateInToday(next) {
                timesToday.append(next)
            }
        }
        guard let nextToday = timesToday.sorted().first else { return nil }
        let timeText = TodayFormatters.time.string(from: nextToday)
        return "\(medicine.nome): \(timeText)"
    }

    private func timeSortValue(for item: TodayTodoItem) -> Int? {
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        return (match.hour * 60) + match.minute
    }

    private func todoTimeDate(for item: TodayTodoItem, medicines: [Medicine], options: Option?) -> Date? {
        if let medicine = medicine(for: item, medicines: medicines), let date = earliestDoseToday(for: medicine, recurrenceManager: RecurrenceManager(context: viewContext)) {
            return date
        }
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        let now = Date()
        return Calendar.current.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
    }

    private func timeComponents(from detail: String) -> (hour: Int, minute: Int)? {
        let pattern = "([0-9]{1,2}):([0-9]{2})"
        guard let range = detail.range(of: pattern, options: .regularExpression) else { return nil }
        let substring = String(detail[range])
        let parts = substring.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let hour = parts[0]
        let minute = parts[1]
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private func hasUpcomingTherapyInNextWeek(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> Bool {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return false }
        let now = Date()
        let limit = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        for therapy in therapies {
            guard let next = nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager) else {
                continue
            }
            if next <= limit { return true }
        }
        return false
    }

    func earliestDoseToday(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> Date? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let upcoming = therapies.compactMap { therapy in
            nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager)
        }
        return upcoming.filter { calendar.isDateInToday($0) }.sorted().first
    }

    func nextUpcomingDoseDate(for therapy: Therapy, medicine: Medicine, now: Date, recurrenceManager: RecurrenceManager) -> Date? {
        recurrenceManager.nextOccurrence(
            rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
            startDate: therapy.start_date ?? now,
            after: now,
            doses: therapy.doses as NSSet?
        )
    }

    func isOutOfStock(_ medicine: Medicine, option: Option?, recurrenceManager: RecurrenceManager) -> Bool {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalLeft <= 0 { return true }
            guard dailyUsage > 0 else { return false }
            return (totalLeft / dailyUsage) < Double(medicine.stockThreshold(option: option))
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            return remaining <= 0
        }
        return false
    }

    func needsPrescriptionBeforePurchase(_ medicine: Medicine, option: Option?, recurrenceManager: RecurrenceManager) -> Bool {
        guard medicine.obbligo_ricetta else { return false }
        if medicine.hasNewPrescritpionRequest() { return false }
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalLeft <= 0 { return true }
            guard dailyUsage > 0 else { return false }
            let days = totalLeft / dailyUsage
            let threshold = Double(medicine.stockThreshold(option: option))
            return days < threshold
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            return remaining <= medicine.stockThreshold(option: option)
        }
        return false
    }

    // MARK: - Helpers per medicine lookup
    private func medicine(for item: TodayTodoItem, medicines: [Medicine]) -> Medicine? {
        if let id = item.medicineID, let medicine = medicines.first(where: { $0.objectID == id }) {
            return medicine
        }
        let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return medicines.first(where: { $0.nome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle })
    }

    private func blockedTherapyInfo(for item: TodayTodoItem, medicines: [Medicine], option: Option?) -> Medicine? {
        guard item.category == .therapy, let med = medicine(for: item, medicines: medicines) else { return nil }
        let rec = RecurrenceManager(context: viewContext)
        let needsRx = needsPrescriptionBeforePurchase(med, option: option, recurrenceManager: rec)
        let outOfStock = isOutOfStock(med, option: option, recurrenceManager: rec)
        guard needsRx || outOfStock else { return nil }
        return med
    }
}
