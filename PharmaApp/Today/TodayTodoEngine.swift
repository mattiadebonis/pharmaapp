import Foundation
import CoreData

struct TodayTodoEngine {
    static func buildState(
        medicines: [Medicine],
        logs: [Log],
        todos: [Todo],
        option: Option?,
        completedTodoIDs: Set<String>,
        recurrenceManager: RecurrenceManager,
        clinicalContext: ClinicalContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayState {
        let sections = computeSections(for: medicines, logs: logs, option: option)
        let insightsContext = buildInsightsContext(
            sections: sections,
            medicines: medicines,
            option: option,
            recurrenceManager: recurrenceManager,
            now: now,
            calendar: calendar
        )
        let urgentIDs = urgentMedicineIDs(
            for: sections,
            option: option,
            recurrenceManager: recurrenceManager,
            now: now,
            calendar: calendar
        )
        let computedTodos = buildTodoItems(
            from: insightsContext,
            medicines: medicines,
            urgentIDs: urgentIDs,
            option: option,
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext,
            now: now,
            calendar: calendar
        )

        let storedItems = todos.compactMap { TodayTodoItem(todo: $0) }
        let sorted = sortTodos(
            storedItems,
            medicines: medicines,
            option: option,
            recurrenceManager: recurrenceManager,
            now: now,
            calendar: calendar
        )
        let filtered = filterDueTherapyItems(
            sorted,
            medicines: medicines,
            recurrenceManager: recurrenceManager,
            now: now,
            calendar: calendar
        )
        let pendingItems = filtered.filter { !completedTodoIDs.contains(completionKey(for: $0)) }
        let purchaseItems = pendingItems.filter { $0.category == .purchase }
        let nonPurchaseItems = pendingItems.filter { $0.category != .purchase }
        let therapyItems = nonPurchaseItems.filter { $0.category == .therapy }
        let otherItems = nonPurchaseItems.filter { $0.category != .therapy }

        return TodayState(
            computedTodos: computedTodos,
            pendingItems: pendingItems,
            therapyItems: therapyItems,
            purchaseItems: purchaseItems,
            otherItems: otherItems,
            showPharmacyCard: !purchaseItems.isEmpty,
            syncToken: syncToken(for: computedTodos)
        )
    }

    static func completionKey(for item: TodayTodoItem) -> String {
        if item.category == .monitoring || item.category == .missedDose {
            return item.id
        }
        if let medID = item.medicineID {
            return "\(item.category.rawValue)|\(medID)"
        }
        return item.id
    }

    static func syncToken(for items: [TodayTodoItem]) -> String {
        items.map { item in
            let detail = item.detail ?? ""
            let medID = item.medicineID?.uriRepresentation().absoluteString ?? ""
            return "\(item.id)|\(item.category.rawValue)|\(item.title)|\(detail)|\(medID)"
        }.joined(separator: "||")
    }

    // MARK: - Insights / Todo building
    static func buildInsightsContext(
        sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]),
        medicines: [Medicine],
        option: Option?,
        recurrenceManager: RecurrenceManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AIInsightsContext? {
        let purchaseLines = sections.purchase.map { medicine in
            "\(medicine.nome): \(purchaseHighlight(for: medicine, option: option, recurrenceManager: recurrenceManager, now: now, calendar: calendar))"
        }
        let therapySources = sections.oggi + sections.purchase
        let therapyLines = therapySources.compactMap { medicine in
            nextDoseTodayHighlight(for: medicine, recurrenceManager: recurrenceManager, now: now, calendar: calendar)
        }
        let upcomingLines = sections.ok.prefix(3).compactMap { medicine in
            nextDoseHighlight(for: medicine, recurrenceManager: recurrenceManager, now: now, calendar: calendar)
        }
        var prescriptionLines: [String] = []
        for medicine in medicines {
            guard needsPrescriptionBeforePurchase(medicine, option: option, recurrenceManager: recurrenceManager) else { continue }
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

    static func buildTodoItems(
        from context: AIInsightsContext?,
        medicines: [Medicine],
        urgentIDs: Set<NSManagedObjectID>,
        option: Option?,
        recurrenceManager: RecurrenceManager,
        clinicalContext: ClinicalContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodayTodoItem] {
        var baseItems: [TodayTodoItem] = []
        if let context {
            baseItems = TodayTodoBuilder.makeTodos(from: context, medicines: medicines, urgentIDs: urgentIDs)
            baseItems = baseItems.filter { [.therapy, .purchase, .prescription].contains($0.category) }
            let blockedMedicineIDs: Set<NSManagedObjectID> = Set(
                baseItems.compactMap { item in
                    guard let info = blockedTherapyInfo(for: item, medicines: medicines, option: option, recurrenceManager: recurrenceManager) else { return nil }
                    return info.objectID
                }
            )
            if !blockedMedicineIDs.isEmpty {
                baseItems = baseItems.filter { item in
                    guard let medID = item.medicineID else { return true }
                    guard blockedMedicineIDs.contains(medID) else { return true }
                    if item.category == .prescription { return false }
                    return true
                }
            }
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
                   needsPrescriptionBeforePurchase(med, option: option, recurrenceManager: recurrenceManager) {
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

        let depletedPurchaseItems = medicines.compactMap { medicine -> TodayTodoItem? in
            guard shouldAddDepletedPurchase(for: medicine, existingItems: baseItems, option: option, urgentIDs: urgentIDs, recurrenceManager: recurrenceManager) else {
                return nil
            }
            let detail = purchaseDetail(for: medicine, option: option, urgentIDs: urgentIDs, recurrenceManager: recurrenceManager)
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
        return baseItems + deadlineItems + clinicalContext.allTodos
    }

    static func sortTodos(
        _ items: [TodayTodoItem],
        medicines: [Medicine],
        option: Option?,
        recurrenceManager: RecurrenceManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodayTodoItem] {
        items.sorted { lhs, rhs in
            if lhs.category == .deadline, rhs.category == .deadline {
                let lDate = deadlineDate(for: lhs, medicines: medicines) ?? .distantFuture
                let rDate = deadlineDate(for: rhs, medicines: medicines) ?? .distantFuture
                if lDate != rDate { return lDate < rDate }
            }
            let lTime = timeSortValue(for: lhs, medicines: medicines, option: option, recurrenceManager: recurrenceManager, now: now, calendar: calendar) ?? Int.max
            let rTime = timeSortValue(for: rhs, medicines: medicines, option: option, recurrenceManager: recurrenceManager, now: now, calendar: calendar) ?? Int.max
            if lTime != rTime { return lTime < rTime }
            if categoryRank(lhs.category) != categoryRank(rhs.category) {
                return categoryRank(lhs.category) < categoryRank(rhs.category)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func timeLabel(
        for item: TodayTodoItem,
        medicines: [Medicine],
        options: Option?,
        recurrenceManager: RecurrenceManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        if item.category == .purchase {
            return "Rifornimenti"
        }
        if item.category == .deadline {
            return "Scadenze"
        }
        guard let date = todoTimeDate(for: item, medicines: medicines, options: options, recurrenceManager: recurrenceManager, now: now, calendar: calendar) else { return nil }
        return TodayFormatters.time.string(from: date)
    }

    static func categoryRank(_ category: TodayTodoItem.Category) -> Int {
        TodayTodoItem.Category.displayOrder.firstIndex(of: category) ?? Int.max
    }

    static func urgentMedicineIDs(
        for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]),
        option: Option?,
        recurrenceManager: RecurrenceManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<NSManagedObjectID> {
        let allMedicines = sections.purchase + sections.oggi + sections.ok
        let urgent = allMedicines.filter {
            isOutOfStock($0, option: option, recurrenceManager: recurrenceManager) && hasUpcomingTherapyInNextWeek(for: $0, recurrenceManager: recurrenceManager, now: now, calendar: calendar)
        }
        return Set(urgent.map { $0.objectID })
    }

    // MARK: - Helpers
    private static func purchaseHighlight(
        for medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager,
        now: Date,
        calendar: Calendar
    ) -> String {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalLeft <= 0 {
                if let nextToday = earliestDoseToday(for: medicine, recurrenceManager: recurrenceManager, now: now, calendar: calendar) {
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

    private static func nextDoseHighlight(
        for medicine: Medicine,
        recurrenceManager: RecurrenceManager,
        now: Date,
        calendar: Calendar
    ) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
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

    private static func nextDoseTodayHighlight(
        for medicine: Medicine,
        recurrenceManager: RecurrenceManager,
        now: Date,
        calendar: Calendar
    ) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
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

    static func timeSortValue(
        for item: TodayTodoItem,
        medicines: [Medicine],
        option: Option?,
        recurrenceManager: RecurrenceManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        if (item.category == .monitoring || item.category == .missedDose),
           let date = timestampFromID(item) {
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
        if item.category == .deadline {
            return nil
        }
        guard let detail = item.detail, let match = TodayFormatting.timeComponents(from: detail) else { return nil }
        return (match.hour * 60) + match.minute
    }

    static func todoTimeDate(
        for item: TodayTodoItem,
        medicines: [Medicine],
        options: Option?,
        recurrenceManager: RecurrenceManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
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
            if let detail = item.detail, let match = TodayFormatting.timeComponents(from: detail) {
                return calendar.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
            }
        }
        if let medicine = medicine(for: item, medicines: medicines), let date = earliestDoseToday(for: medicine, recurrenceManager: recurrenceManager, now: now, calendar: calendar) {
            return date
        }
        guard let detail = item.detail, let match = TodayFormatting.timeComponents(from: detail) else { return nil }
        return calendar.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
    }

    private static func timestampFromID(_ item: TodayTodoItem) -> Date? {
        let parts = item.id.split(separator: "|")
        guard let last = parts.last, let seconds = TimeInterval(String(last)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func deadlineDate(for item: TodayTodoItem, medicines: [Medicine]) -> Date? {
        guard item.category == .deadline, let id = item.medicineID else { return nil }
        return medicines.first(where: { $0.objectID == id })?.deadlineMonthStartDate
    }

    private static func hasUpcomingTherapyInNextWeek(
        for medicine: Medicine,
        recurrenceManager: RecurrenceManager,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return false }
        let limit = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        for therapy in therapies {
            guard let next = nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager) else {
                continue
            }
            if next <= limit { return true }
        }
        return false
    }

    static func earliestDoseToday(
        for medicine: Medicine,
        recurrenceManager: RecurrenceManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let upcoming = therapies.compactMap { therapy in
            nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager)
        }
        return upcoming.filter { calendar.isDateInToday($0) }.sorted().first
    }

    private static func nextUpcomingDoseDate(
        for therapy: Therapy,
        medicine: Medicine,
        now: Date,
        recurrenceManager: RecurrenceManager
    ) -> Date? {
        recurrenceManager.nextOccurrence(
            rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
            startDate: therapy.start_date ?? now,
            after: now,
            doses: therapy.doses as NSSet?
        )
    }

    static func isOutOfStock(
        _ medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> Bool {
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

    static func needsPrescriptionBeforePurchase(
        _ medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> Bool {
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

    private static func shouldAddDepletedPurchase(
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

    private static func purchaseDetail(
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

    private static func purchaseStockStatusLabel(
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

    private static func medicine(for item: TodayTodoItem, medicines: [Medicine]) -> Medicine? {
        if let id = item.medicineID, let medicine = medicines.first(where: { $0.objectID == id }) {
            return medicine
        }
        let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return medicines.first(where: { $0.nome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle })
    }

    private static func blockedTherapyInfo(
        for item: TodayTodoItem,
        medicines: [Medicine],
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> Medicine? {
        guard item.category == .therapy, let med = medicine(for: item, medicines: medicines) else { return nil }
        let needsRx = needsPrescriptionBeforePurchase(med, option: option, recurrenceManager: recurrenceManager)
        let outOfStock = isOutOfStock(med, option: option, recurrenceManager: recurrenceManager)
        guard needsRx || outOfStock else { return nil }
        return med
    }

    private static func deadlineTodoItems(from medicines: [Medicine]) -> [TodayTodoItem] {
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

    private static func filterDueTherapyItems(
        _ items: [TodayTodoItem],
        medicines: [Medicine],
        recurrenceManager: RecurrenceManager,
        now: Date,
        calendar: Calendar
    ) -> [TodayTodoItem] {
        items.filter { item in
            if item.category == .therapy, let med = medicine(for: item, medicines: medicines) {
                let hasIntakeToday = med.hasIntakeToday(from: now, recurrenceManager: recurrenceManager, calendar: calendar)
                let hasLoggedToday = !med.effectiveIntakeLogs(on: now, calendar: calendar).isEmpty
                return hasIntakeToday && !hasLoggedToday
            }
            return true
        }
    }
}
