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
        var baseItems: [TodayTodoItem] = []
        if let context {
            baseItems = TodayTodoBuilder.makeTodos(from: context, medicines: medicines, urgentIDs: urgentIDs)
            baseItems = baseItems.filter { [.therapy, .purchase, .prescription].contains($0.category) }
            let blockedMedicineIDs: Set<NSManagedObjectID> = Set(
                baseItems.compactMap { item in
                    guard let info = blockedTherapyInfo(for: item, medicines: medicines, option: option) else { return nil }
                    return info.objectID
                }
            )
            let rec = RecurrenceManager(context: viewContext)
            if !blockedMedicineIDs.isEmpty {
                baseItems = baseItems.filter { item in
                    guard let medID = item.medicineID else { return true }
                    guard blockedMedicineIDs.contains(medID) else { return true }
                    if item.category == .prescription { return false }
                    return true
                }
            }
            // Se esiste un todo di acquisto per un medicinale, rimuovi il todo di ricetta duplicato:
            let purchaseIDs: Set<NSManagedObjectID> = Set(baseItems.compactMap { item in
                item.category == .purchase ? item.medicineID : nil
            })
            if !purchaseIDs.isEmpty {
                baseItems = baseItems.filter { item in
                    if item.category == .prescription, let medID = item.medicineID {
                        return !purchaseIDs.contains(medID)
                    }
                    return true
                }
            }
            baseItems = baseItems.map { item in
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

        }

        let rec = RecurrenceManager(context: viewContext)
        let depletedPurchaseItems = medicines.compactMap { medicine -> TodayTodoItem? in
            guard shouldAddDepletedPurchase(for: medicine, existingItems: baseItems, option: option, urgentIDs: urgentIDs, recurrenceManager: rec) else {
                return nil
            }
            let detail = purchaseDetail(for: medicine, option: option, urgentIDs: urgentIDs, recurrenceManager: rec)
            let id = "purchase|depleted|\(medicine.objectID.uriRepresentation().absoluteString)"
            return TodayTodoItem(
                id: id,
                title: medicine.nome,
                detail: detail,
                category: .purchase,
                medicineID: medicine.objectID
            )
        }
        baseItems.append(contentsOf: depletedPurchaseItems)
        let deadlineItems = deadlineTodoItems(from: medicines)
        let clinicalContext = ClinicalContextBuilder(context: viewContext).build(for: medicines)
        return baseItems + deadlineItems + clinicalContext.allTodos
    }

    private func deadlineTodoItems(from medicines: [Medicine]) -> [TodayTodoItem] {
        let candidates: [(Medicine, Int, String, Date)] = medicines.compactMap { medicine in
            guard let months = medicine.monthsUntilDeadline,
                  months < 0,
                  let label = medicine.deadlineLabel,
                  let date = medicine.deadlineMonthStartDate else {
                return nil
            }
            return (medicine, months, label, date)
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.3 != rhs.3 { return lhs.3 < rhs.3 }
                return lhs.0.nome.localizedCaseInsensitiveCompare(rhs.0.nome) == .orderedAscending
            }
            .map { medicine, _, label, _ in
                let detail = "Scaduto \(label)"
                let id = "purchase|deadline|\(medicine.objectID.uriRepresentation().absoluteString)|\(label)"
                return TodayTodoItem(
                    id: id,
                    title: medicine.nome,
                    detail: detail,
                    category: .purchase,
                    medicineID: medicine.objectID
                )
            }
    }

    @MainActor
    func syncTodos(
        from items: [TodayTodoItem],
        medicines: [Medicine],
        option: Option?
    ) {
        let context = viewContext
        let now = Date()
        let request: NSFetchRequest<Todo> = Todo.fetchRequest()
        let existing: [Todo]
        do {
            existing = try context.fetch(request)
        } catch {
            print("⚠️ syncTodos: fetch failed \(error)")
            return
        }

        var bySourceID: [String: Todo] = [:]
        for todo in existing {
            bySourceID[todo.source_id] = todo
        }

        var seen: Set<String> = []
        for item in items {
            let sourceID = item.id
            seen.insert(sourceID)
            let todo = bySourceID[sourceID] ?? Todo(context: context)
            if bySourceID[sourceID] == nil {
                todo.id = UUID()
                todo.created_at = now
            }
            todo.source_id = sourceID
            todo.title = item.title
            todo.detail = item.detail
            todo.category = item.category.rawValue
            todo.updated_at = now
            todo.due_at = todoTimeDate(for: item, medicines: medicines, options: option)
            todo.medicine = medicine(for: item, medicines: medicines)
        }

        for todo in existing where !seen.contains(todo.source_id) {
            context.delete(todo)
        }

        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("⚠️ syncTodos: save failed \(error)")
        }
    }

    func sortTodos(_ items: [TodayTodoItem]) -> [TodayTodoItem] {
        items.sorted { lhs, rhs in
            if lhs.category == .deadline, rhs.category == .deadline {
                let lDate = deadlineDate(for: lhs) ?? .distantFuture
                let rDate = deadlineDate(for: rhs) ?? .distantFuture
                if lDate != rDate { return lDate < rDate }
            }
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
                let lhsPriority = groupPriority(lhs.label)
                let rhsPriority = groupPriority(rhs.label)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
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

    private func groupPriority(_ label: String) -> Int {
        switch label {
        case "Rifornimenti":
            return 2
        case "Scadenze":
            return 1
        default:
            return 0
        }
    }

    func timeLabel(for item: TodayTodoItem, medicines: [Medicine], options: Option?) -> String? {
        if item.category == .purchase {
            return "Rifornimenti"
        }
        if item.category == .deadline {
            return "Scadenze"
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
        if (item.category == .monitoring || item.category == .missedDose),
           let date = timestampFromID(item) {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
        if item.category == .deadline {
            return nil
        }
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        return (match.hour * 60) + match.minute
    }

    private func todoTimeDate(for item: TodayTodoItem, medicines: [Medicine], options: Option?) -> Date? {
        if item.category == .deadline,
           let medicine = medicine(for: item, medicines: medicines),
           let date = medicine.deadlineMonthStartDate {
            return date
        }
        if item.category == .purchase,
           item.id.hasPrefix("purchase|deadline|"),
           let medicine = medicine(for: item, medicines: medicines),
           let date = medicine.deadlineMonthStartDate {
            return date
        }
        if item.category == .monitoring || item.category == .missedDose {
            if let date = timestampFromID(item) {
                return date
            }
            if let detail = item.detail, let match = timeComponents(from: detail) {
                let now = Date()
                return Calendar.current.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
            }
        }
        if let medicine = medicine(for: item, medicines: medicines), let date = earliestDoseToday(for: medicine, recurrenceManager: RecurrenceManager(context: viewContext)) {
            return date
        }
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        let now = Date()
        return Calendar.current.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
    }

    private func timestampFromID(_ item: TodayTodoItem) -> Date? {
        let parts = item.id.split(separator: "|")
        guard let last = parts.last, let seconds = TimeInterval(String(last)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
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

    private func deadlineDate(for item: TodayTodoItem) -> Date? {
        guard item.category == .deadline, let id = item.medicineID else { return nil }
        guard let medicine = try? viewContext.existingObject(with: id) as? Medicine else { return nil }
        return medicine.deadlineMonthStartDate
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

    private func shouldAddDepletedPurchase(
        for medicine: Medicine,
        existingItems: [TodayTodoItem],
        option: Option?,
        urgentIDs: Set<NSManagedObjectID>,
        recurrenceManager: RecurrenceManager
    ) -> Bool {
        guard isOutOfStock(medicine, option: option, recurrenceManager: recurrenceManager) else { return false }

        if existingItems.contains(where: { $0.category == .purchase && $0.medicineID == medicine.objectID }) {
            return false
        }
        return true
    }

    private func purchaseDetail(
        for medicine: Medicine,
        option: Option?,
        urgentIDs: Set<NSManagedObjectID>,
        recurrenceManager: RecurrenceManager
    ) -> String? {
        var parts: [String] = []
        if let status = purchaseStockStatusLabel(for: medicine, option: option, recurrenceManager: recurrenceManager) {
            parts.append(status)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func purchaseStockStatusLabel(
        for medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> String? {
        let threshold = medicine.stockThreshold(option: option)
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalLeft <= 0 {
                return "Scorte finite"
            }
            guard dailyUsage > 0 else { return nil }
            let days = totalLeft / dailyUsage
            return days < Double(threshold) ? "Scorte in esaurimento" : nil
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            if remaining <= 0 {
                return "Scorte finite"
            }
            return remaining < threshold ? "Scorte in esaurimento" : nil
        }
        return nil
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
