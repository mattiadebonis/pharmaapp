import Foundation

public struct TodayDoseInfo: Equatable {
    public let date: Date
    public let personName: String?
    public let therapyId: TherapyId

    public init(date: Date, personName: String?, therapyId: TherapyId) {
        self.date = date
        self.personName = personName
        self.therapyId = therapyId
    }
}

public struct TodayStateBuilder {
    public init() {}

    public static func buildState(input: TodayStateInput) -> TodayState {
        let recurrenceService = RecurrenceService()
        let sections = computeSections(
            for: input.medicines,
            option: input.option,
            recurrenceService: recurrenceService,
            now: input.now,
            calendar: input.calendar
        )
        let insightsContext = buildInsightsContext(
            sections: sections,
            medicines: input.medicines,
            option: input.option,
            recurrenceService: recurrenceService,
            now: input.now,
            calendar: input.calendar
        )
        let urgentIDs = urgentMedicineIDs(
            for: sections,
            option: input.option,
            recurrenceService: recurrenceService,
            now: input.now,
            calendar: input.calendar
        )
        let clinicalContext = TodayClinicalContextBuilder(
            recurrenceService: recurrenceService,
            calendar: input.calendar
        ).build(for: input.medicines, now: input.now)

        let computedTodos = buildTodoItems(
            from: insightsContext,
            medicines: input.medicines,
            urgentIds: urgentIDs,
            option: input.option,
            recurrenceService: recurrenceService,
            clinicalContext: clinicalContext,
            now: input.now,
            calendar: input.calendar
        )

        let storedItems = input.todos.compactMap { todoItem(from: $0) }
        let sorted = sortTodos(
            storedItems,
            medicines: input.medicines,
            option: input.option,
            recurrenceService: recurrenceService,
            now: input.now,
            calendar: input.calendar
        )
        let filtered = filterDueTherapyItems(
            sorted,
            medicines: input.medicines,
            recurrenceService: recurrenceService,
            now: input.now,
            calendar: input.calendar
        )
        let pendingItems = filtered.filter { item in
            if item.category == .therapy { return true }
            return !input.completedTodoIDs.contains(completionKey(for: item))
        }
        let purchaseItems = pendingItems.filter { $0.category == .purchase }
        let nonPurchaseItems = pendingItems.filter { $0.category != .purchase }
        let therapyItems = nonPurchaseItems.filter { $0.category == .therapy }
        let otherItems = nonPurchaseItems.filter { $0.category != .therapy }

        let timeLabels: [String: TodayTimeLabel] = Dictionary(
            pendingItems.compactMap { item in
                guard let label = timeLabel(
                    for: item,
                    medicines: input.medicines,
                    option: input.option,
                    recurrenceService: recurrenceService,
                    now: input.now,
                    calendar: input.calendar
                ) else { return nil }
                return (item.id, label)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let medicineStatuses = buildMedicineStatuses(
            medicines: input.medicines,
            option: input.option,
            recurrenceService: recurrenceService,
            now: input.now,
            calendar: input.calendar
        )
        let blockedTherapyStatuses = buildBlockedTherapyStatuses(
            items: pendingItems,
            medicineStatuses: medicineStatuses
        )

        return TodayState(
            computedTodos: computedTodos,
            pendingItems: pendingItems,
            therapyItems: therapyItems,
            purchaseItems: purchaseItems,
            otherItems: otherItems,
            showPharmacyCard: !purchaseItems.isEmpty,
            timeLabels: timeLabels,
            medicineStatuses: medicineStatuses,
            blockedTherapyStatuses: blockedTherapyStatuses,
            syncToken: syncToken(for: computedTodos)
        )
    }

    public static func completionKey(for item: TodayTodoItem) -> String {
        if item.category == .monitoring || item.category == .missedDose || item.category == .therapy {
            return item.id
        }
        if let medId = item.medicineId {
            return "\(item.category.rawValue)|\(medId.rawValue.uuidString)"
        }
        return item.id
    }

    public static func syncToken(for items: [TodayTodoItem]) -> String {
        items.map { item in
            let detail = item.detail ?? ""
            let medId = item.medicineId?.rawValue.uuidString ?? ""
            return "\(item.id)|\(item.category.rawValue)|\(item.title)|\(detail)|\(medId)"
        }.joined(separator: "||")
    }

    public static func todoTimeDate(
        for item: TodayTodoItem,
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let recurrenceService = RecurrenceService()
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
                return calendar.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
            }
        }
        if let medicine = medicine(for: item, medicines: medicines),
           let date = earliestDoseToday(
            for: medicine,
            recurrenceService: recurrenceService,
            now: now,
            calendar: calendar
           ) {
            return date
        }
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        return calendar.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
    }

    public static func nextUpcomingDoseDate(
        for medicine: MedicineSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let recurrenceService = RecurrenceService()
        guard !medicine.therapies.isEmpty else { return nil }
        let upcoming = medicine.therapies.compactMap { therapy in
            nextUpcomingDoseDate(
                for: therapy,
                medicine: medicine,
                now: now,
                recurrenceService: recurrenceService
            )
        }
        return upcoming.sorted().first
    }

    public static func nextDoseTodayInfo(
        for medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        now: Date,
        calendar: Calendar = .current
    ) -> TodayDoseInfo? {
        let recurrenceService = RecurrenceService()
        guard !medicine.therapies.isEmpty else { return nil }
        let manualEnabled = manualIntakeEnabled(for: medicine, option: option, therapies: medicine.therapies)
        guard manualEnabled else { return nil }

        var best: (date: Date, personName: String?, therapyId: TherapyId)?
        for therapy in medicine.therapies {
            guard let next = nextUpcomingDoseDateConsideringIntake(
                for: therapy,
                medicine: medicine,
                now: now,
                recurrenceService: recurrenceService,
                calendar: calendar
            ) else { continue }
            guard calendar.isDateInToday(next) else { continue }
            let personName = therapy.personName
            if best == nil || next < best!.date {
                best = (next, personName, therapy.id)
            }
        }
        guard let best else { return nil }
        return TodayDoseInfo(date: best.date, personName: best.personName, therapyId: best.therapyId)
    }

    public static func isOutOfStock(
        _ medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let recurrenceService = RecurrenceService()
        return isOutOfStock(
            medicine,
            option: option,
            recurrenceService: recurrenceService,
            now: now,
            calendar: calendar
        )
    }

    public static func needsPrescriptionBeforePurchase(
        _ medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let recurrenceService = RecurrenceService()
        return needsPrescriptionBeforePurchase(
            medicine,
            option: option,
            recurrenceService: recurrenceService,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Insights / Todo building
    private struct TodayInsightsContext {
        let purchaseHighlights: [String]
        let therapyHighlights: [String]
        let upcomingHighlights: [String]
        let prescriptionHighlights: [String]
        let pharmacySuggestion: String?

        var hasSignals: Bool {
            !purchaseHighlights.isEmpty ||
            !therapyHighlights.isEmpty ||
            !upcomingHighlights.isEmpty ||
            !prescriptionHighlights.isEmpty ||
            pharmacySuggestion != nil
        }
    }

    private static func buildInsightsContext(
        sections: (purchase: [MedicineSnapshot], oggi: [MedicineSnapshot], ok: [MedicineSnapshot]),
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> TodayInsightsContext? {
        let validPurchase = sections.purchase.filter { isVisibleInToday($0) }
        let validOggi = sections.oggi.filter { isVisibleInToday($0) }

        let purchaseLines = validPurchase.map { medicine in
            "\(medicine.name): \(purchaseHighlight(for: medicine, option: option, recurrenceService: recurrenceService, now: now, calendar: calendar))"
        }
        let therapySources = validOggi + validPurchase
        let therapyLines = therapySources.compactMap { medicine in
            nextDoseTodayHighlight(for: medicine, recurrenceService: recurrenceService, now: now, calendar: calendar)
        }
        let upcomingLines = sections.ok.prefix(3).compactMap { medicine in
            nextDoseHighlight(for: medicine, recurrenceService: recurrenceService, now: now, calendar: calendar)
        }
        var prescriptionLines: [String] = []
        for medicine in medicines {
            guard needsPrescriptionBeforePurchase(medicine, option: option, recurrenceService: recurrenceService, now: now, calendar: calendar) else {
                continue
            }
            prescriptionLines.append(medicine.name)
            if prescriptionLines.count >= 6 { break }
        }
        let context = TodayInsightsContext(
            purchaseHighlights: purchaseLines,
            therapyHighlights: therapyLines,
            upcomingHighlights: upcomingLines,
            prescriptionHighlights: prescriptionLines,
            pharmacySuggestion: purchaseLines.isEmpty ? nil : nil
        )
        return context.hasSignals ? context : nil
    }

    private static func buildTodoItems(
        from context: TodayInsightsContext?,
        medicines: [MedicineSnapshot],
        urgentIds: Set<MedicineId>,
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        clinicalContext: TodayClinicalContext,
        now: Date,
        calendar: Calendar
    ) -> [TodayTodoItem] {
        var baseItems: [TodayTodoItem] = []
        if let context {
            baseItems = makeTodos(from: context, medicines: medicines, urgentIds: urgentIds)
            baseItems = baseItems.filter { [.therapy, .purchase, .prescription].contains($0.category) }
            let blockedMedicineIds: Set<MedicineId> = Set(
                baseItems.compactMap { item in
                    guard let info = blockedTherapyInfo(
                        for: item,
                        medicines: medicines,
                        option: option,
                        recurrenceService: recurrenceService,
                        now: now,
                        calendar: calendar
                    ) else { return nil }
                    return info.id
                }
            )
            if !blockedMedicineIds.isEmpty {
                baseItems = baseItems.filter { item in
                    guard let medId = item.medicineId else { return true }
                    guard blockedMedicineIds.contains(medId) else { return true }
                    if item.category == .prescription { return false }
                    return true
                }
            }
            let purchaseIDs: Set<MedicineId> = Set(baseItems.compactMap { item in
                item.category == .purchase ? item.medicineId : nil
            })
            if !purchaseIDs.isEmpty {
                baseItems = baseItems.filter { item in
                    if item.category == .prescription, let medId = item.medicineId {
                        return !purchaseIDs.contains(medId)
                    }
                    return true
                }
            }
            baseItems = baseItems.map { item in
                if item.category == .prescription,
                   let med = medicine(for: item, medicines: medicines),
                   needsPrescriptionBeforePurchase(med, option: option, recurrenceService: recurrenceService, now: now, calendar: calendar) {
                    return TodayTodoItem(
                        id: "purchase|rx|\(item.id)",
                        title: item.title,
                        detail: item.detail,
                        category: .purchase,
                        medicineId: item.medicineId
                    )
                }
                return item
            }
        }

        let missingTherapies = supplementalTherapyItems(
            medicines: medicines,
            existingItems: baseItems,
            recurrenceService: recurrenceService,
            now: now,
            calendar: calendar
        )
        baseItems.append(contentsOf: missingTherapies)

        let depletedPurchaseItems = medicines.compactMap { medicine -> TodayTodoItem? in
            guard shouldAddDepletedPurchase(
                for: medicine,
                existingItems: baseItems,
                option: option,
                urgentIds: urgentIds,
                recurrenceService: recurrenceService,
                now: now,
                calendar: calendar
            ) else {
                return nil
            }
            let detail = purchaseDetail(
                for: medicine,
                option: option,
                urgentIds: urgentIds,
                recurrenceService: recurrenceService,
                now: now,
                calendar: calendar
            )
            let id = "purchase|depleted|\(medicine.externalKey)"
            return TodayTodoItem(
                id: id,
                title: medicine.name,
                detail: detail,
                category: .purchase,
                medicineId: medicine.id
            )
        }
        baseItems.append(contentsOf: depletedPurchaseItems)
        let deadlineItems = deadlineTodoItems(from: medicines)
        return baseItems + deadlineItems + clinicalContext.allTodos
    }

    private static func makeTodos(
        from context: TodayInsightsContext,
        medicines: [MedicineSnapshot],
        urgentIds: Set<MedicineId>
    ) -> [TodayTodoItem] {
        var items: [TodayTodoItem] = []
        let medIndex: [String: MedicineSnapshot] = {
            var dict: [String: MedicineSnapshot] = [:]
            for med in medicines {
                dict[med.name.lowercased()] = med
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
                    medicineId: medIndex[parsed.name.lowercased()]?.id
                )
            )
        }

        for highlight in context.purchaseHighlights {
            guard let parsed = parsePurchaseHighlight(highlight) else { continue }
            let med = medIndex[parsed.name.lowercased()]
            let medId = med?.id
            let salt = med?.latestLogSalt ?? ""
            let detailWithUrgency = detailForAction(
                base: parsed.detail,
                medicine: med,
                urgentIds: urgentIds
            )
            items.append(
                TodayTodoItem(
                    id: "purchase|\(parsed.name.lowercased())|\(parsed.status.rawValue)|\(salt)",
                    title: parsed.name,
                    detail: detailWithUrgency,
                    category: .purchase,
                    medicineId: medId
                )
            )
        }

        for highlight in context.prescriptionHighlights {
            guard let parsed = parseHighlight(highlight) else { continue }
            let med = medIndex[parsed.name.lowercased()]
            let medId = med?.id
            let salt = med?.latestLogSalt ?? ""
            let baseDetail: String?
            if let med, med.hasNewPrescriptionRequest() {
                baseDetail = parsed.detail
            } else {
                baseDetail = nil
            }
            let detailWithUrgency = detailForAction(
                base: baseDetail,
                medicine: med,
                urgentIds: urgentIds
            )
            items.append(
                TodayTodoItem(
                    id: "prescription|\(parsed.id)|\(salt)",
                    title: parsed.name,
                    detail: detailWithUrgency,
                    category: .prescription,
                    medicineId: medId
                )
            )
        }

        return items
    }

    private static func sortTodos(
        _ items: [TodayTodoItem],
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> [TodayTodoItem] {
        items.sorted { lhs, rhs in
            if lhs.category == .deadline, rhs.category == .deadline {
                let lDate = deadlineDate(for: lhs, medicines: medicines) ?? .distantFuture
                let rDate = deadlineDate(for: rhs, medicines: medicines) ?? .distantFuture
                if lDate != rDate { return lDate < rDate }
            }
            let lTime = timeSortValue(
                for: lhs,
                medicines: medicines,
                option: option,
                recurrenceService: recurrenceService,
                now: now,
                calendar: calendar
            ) ?? Int.max
            let rTime = timeSortValue(
                for: rhs,
                medicines: medicines,
                option: option,
                recurrenceService: recurrenceService,
                now: now,
                calendar: calendar
            ) ?? Int.max
            if lTime != rTime { return lTime < rTime }
            if categoryRank(lhs.category) != categoryRank(rhs.category) {
                return categoryRank(lhs.category) < categoryRank(rhs.category)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func timeLabel(
        for item: TodayTodoItem,
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> TodayTimeLabel? {
        if item.category == .purchase {
            return .category(.purchase)
        }
        if item.category == .deadline {
            return .category(.deadline)
        }
        guard let date = todoTimeDate(
            for: item,
            medicines: medicines,
            option: option,
            now: now,
            calendar: calendar
        ) else { return nil }
        return .time(date)
    }

    private static func categoryRank(_ category: TodayTodoCategory) -> Int {
        TodayTodoCategory.displayOrder.firstIndex(of: category) ?? Int.max
    }

    private static func urgentMedicineIDs(
        for sections: (purchase: [MedicineSnapshot], oggi: [MedicineSnapshot], ok: [MedicineSnapshot]),
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> Set<MedicineId> {
        let allMedicines = sections.purchase + sections.oggi + sections.ok
        let urgent = allMedicines.filter {
            isVisibleInToday($0) &&
            isOutOfStock($0, option: option, recurrenceService: recurrenceService, now: now, calendar: calendar) &&
            hasUpcomingTherapyInNextWeek(for: $0, recurrenceService: recurrenceService, now: now, calendar: calendar)
        }
        return Set(urgent.map { $0.id })
    }

    private static func computeSections(
        for medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> (purchase: [MedicineSnapshot], oggi: [MedicineSnapshot], ok: [MedicineSnapshot]) {
        enum StockStatus {
            case ok
            case low
            case critical
            case unknown
        }

        func remainingUnits(for medicine: MedicineSnapshot) -> Int? {
            if !medicine.therapies.isEmpty {
                return medicine.therapies.reduce(0) { $0 + $1.leftoverUnits }
            }
            return medicine.stockUnitsWithoutTherapy
        }

        func nextOccurrence(for medicine: MedicineSnapshot) -> Date? {
            guard !medicine.therapies.isEmpty else { return nil }
            var best: Date? = nil
            for therapy in medicine.therapies {
                let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
                let startDate = therapy.startDate ?? now
                if let date = recurrenceService.nextOccurrence(
                    rule: rule,
                    startDate: startDate,
                    after: now,
                    doses: therapy.doses,
                    calendar: calendar
                ) {
                    if best == nil || date < best! { best = date }
                }
            }
            return best
        }

        func deadlineDate(for medicine: MedicineSnapshot) -> Date {
            medicine.deadlineMonthStartDate ?? Date.distantFuture
        }

        func occursToday(_ therapy: TherapySnapshot) -> Bool {
            let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.startDate ?? now
            let perDay = max(1, therapy.doses.count)
            let allowed = recurrenceService.allowedEvents(
                on: now,
                rule: rule,
                startDate: start,
                dosesPerDay: perDay,
                calendar: calendar
            )
            return allowed > 0
        }

        func stockStatus(for medicine: MedicineSnapshot) -> StockStatus {
            let threshold = medicine.stockThreshold(option: option)
            if !medicine.therapies.isEmpty {
                var totalLeftover: Double = 0
                var totalDailyUsage: Double = 0
                for therapy in medicine.therapies {
                    totalLeftover += Double(therapy.leftoverUnits)
                    totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
                }
                if totalDailyUsage <= 0 {
                    return totalLeftover > 0 ? .ok : .unknown
                }
                let coverage = totalLeftover / totalDailyUsage
                if coverage <= 0 { return .critical }
                return coverage < Double(threshold) ? .low : .ok
            }
            if let remaining = medicine.stockUnitsWithoutTherapy {
                if remaining <= 0 { return .critical }
                return remaining < threshold ? .low : .ok
            }
            return .unknown
        }

        var purchase: [MedicineSnapshot] = []
        var oggi: [MedicineSnapshot] = []
        var ok: [MedicineSnapshot] = []

        for medicine in medicines {
            let status = stockStatus(for: medicine)
            if status == .critical || status == .low {
                purchase.append(medicine)
                continue
            }
            if !medicine.therapies.isEmpty, medicine.therapies.contains(where: { occursToday($0) }) {
                oggi.append(medicine)
            } else {
                ok.append(medicine)
            }
        }

        oggi.sort { m1, m2 in
            let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
            let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
            if d1 == d2 {
                let r1 = remainingUnits(for: m1) ?? Int.max
                let r2 = remainingUnits(for: m2) ?? Int.max
                if r1 == r2 {
                    let deadline1 = deadlineDate(for: m1)
                    let deadline2 = deadlineDate(for: m2)
                    if deadline1 != deadline2 { return deadline1 < deadline2 }
                    return m1.name.localizedCaseInsensitiveCompare(m2.name) == .orderedAscending
                }
                return r1 < r2
            }
            return d1 < d2
        }

        purchase.sort { m1, m2 in
            let s1 = stockStatus(for: m1)
            let s2 = stockStatus(for: m2)
            if s1 != s2 { return (s1 == .critical) && (s2 != .critical) }
            let r1 = remainingUnits(for: m1) ?? Int.max
            let r2 = remainingUnits(for: m2) ?? Int.max
            if r1 == r2 {
                let deadline1 = deadlineDate(for: m1)
                let deadline2 = deadlineDate(for: m2)
                if deadline1 != deadline2 { return deadline1 < deadline2 }
                return m1.name.localizedCaseInsensitiveCompare(m2.name) == .orderedAscending
            }
            return r1 < r2
        }

        ok.sort { m1, m2 in
            let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
            let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
            if d1 == d2 {
                let r1 = remainingUnits(for: m1) ?? Int.max
                let r2 = remainingUnits(for: m2) ?? Int.max
                if r1 == r2 {
                    let deadline1 = deadlineDate(for: m1)
                    let deadline2 = deadlineDate(for: m2)
                    if deadline1 != deadline2 { return deadline1 < deadline2 }
                    return m1.name.localizedCaseInsensitiveCompare(m2.name) == .orderedAscending
                }
                return r1 < r2
            }
            return d1 < d2
        }

        return (purchase, oggi, ok)
    }

    private static func purchaseHighlight(
        for medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> String {
        if !medicine.therapies.isEmpty {
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for therapy in medicine.therapies {
                totalLeft += Double(therapy.leftoverUnits)
                totalDaily += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
            }
            if totalLeft <= 0 {
                if let nextToday = earliestDoseToday(
                    for: medicine,
                    recurrenceService: recurrenceService,
                    now: now,
                    calendar: calendar
                ) {
                    let fmt = DateFormatter()
                    fmt.timeStyle = .short
                    return "scorte terminate · da prendere alle \(fmt.string(from: nextToday))"
                }
                return "scorte terminate"
            }
            guard totalDaily > 0 else { return "copertura non stimabile" }
            let days = Int(totalLeft / totalDaily)
            if days <= 0 { return "scorte terminate" }
            return days == 1 ? "copertura per 1 giorno" : "copertura per \(days) giorni"
        }
        if let remaining = medicine.stockUnitsWithoutTherapy {
            if remaining <= 0 { return "nessuna unità residua" }
            if remaining < 5 { return "solo \(remaining) unità" }
            return "\(remaining) unità disponibili"
        }
        return "scorte non monitorate"
    }

    private static func nextDoseHighlight(
        for medicine: MedicineSnapshot,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> String? {
        guard !medicine.therapies.isEmpty else { return nil }
        let upcomingDates = medicine.therapies.compactMap { therapy in
            nextUpcomingDoseDate(
                for: therapy,
                medicine: medicine,
                now: now,
                recurrenceService: recurrenceService
            )
        }
        guard let next = upcomingDates.sorted().first else { return nil }
        if calendar.isDateInToday(next) {
            return "\(medicine.name): \(timeFormatter.string(from: next))"
        } else if calendar.isDateInTomorrow(next) {
            return "\(medicine.name): domani"
        }
        let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
        return "\(medicine.name): \(fmt.string(from: next))"
    }

    private static func nextDoseTodayHighlight(
        for medicine: MedicineSnapshot,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> String? {
        guard !medicine.therapies.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        var timesToday: [Date] = []
        for therapy in medicine.therapies {
            let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
            let startDate = therapy.startDate ?? now
            let next = recurrenceService.nextOccurrence(
                rule: rule,
                startDate: startDate,
                after: today,
                doses: therapy.doses,
                calendar: calendar
            )
            if let next, calendar.isDateInToday(next) {
                timesToday.append(next)
            }
        }
        guard let nextToday = timesToday.sorted().first else { return nil }
        let timeText = timeFormatter.string(from: nextToday)
        return "\(medicine.name): \(timeText)"
    }

    private static func timeSortValue(
        for item: TodayTodoItem,
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> Int? {
        if (item.category == .monitoring || item.category == .missedDose),
           let date = timestampFromID(item) {
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
        if item.category == .deadline {
            return nil
        }
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        return (match.hour * 60) + match.minute
    }

    private static func timestampFromID(_ item: TodayTodoItem) -> Date? {
        let parts = item.id.split(separator: "|")
        guard let last = parts.last, let seconds = TimeInterval(String(last)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func deadlineDate(for item: TodayTodoItem, medicines: [MedicineSnapshot]) -> Date? {
        guard item.category == .deadline, let id = item.medicineId else { return nil }
        return medicines.first(where: { $0.id == id })?.deadlineMonthStartDate
    }

    private static func hasUpcomingTherapyInNextWeek(
        for medicine: MedicineSnapshot,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard !medicine.therapies.isEmpty else { return false }
        let limit = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        for therapy in medicine.therapies {
            guard let next = nextUpcomingDoseDate(
                for: therapy,
                medicine: medicine,
                now: now,
                recurrenceService: recurrenceService
            ) else { continue }
            if next <= limit { return true }
        }
        return false
    }

    private static func earliestDoseToday(
        for medicine: MedicineSnapshot,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard !medicine.therapies.isEmpty else { return nil }
        let upcoming = medicine.therapies.compactMap { therapy in
            nextUpcomingDoseDate(
                for: therapy,
                medicine: medicine,
                now: now,
                recurrenceService: recurrenceService
            )
        }
        return upcoming.filter { calendar.isDateInToday($0) }.sorted().first
    }

    private static func nextUpcomingDoseDate(
        for therapy: TherapySnapshot,
        medicine: MedicineSnapshot,
        now: Date,
        recurrenceService: RecurrenceService
    ) -> Date? {
        recurrenceService.nextOccurrence(
            rule: recurrenceService.parseRecurrenceString(therapy.rrule ?? ""),
            startDate: therapy.startDate ?? now,
            after: now,
            doses: therapy.doses
        )
    }

    private static func isOutOfStock(
        _ medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard isVisibleInToday(medicine) else { return false }

        if !medicine.therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in medicine.therapies {
                totalLeft += Double(therapy.leftoverUnits)
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
            }
            if totalLeft <= 0 { return true }
            guard dailyUsage > 0 else { return false }
            return (totalLeft / dailyUsage) < Double(medicine.stockThreshold(option: option))
        }
        if let remaining = medicine.stockUnitsWithoutTherapy {
            return remaining <= 0
        }
        return false
    }

    private static func needsPrescriptionBeforePurchase(
        _ medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard medicine.requiresPrescription else { return false }
        guard isVisibleInToday(medicine) else { return false }

        if medicine.hasEffectivePrescriptionReceived() { return false }
        if !medicine.therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in medicine.therapies {
                totalLeft += Double(therapy.leftoverUnits)
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
            }
            if totalLeft <= 0 { return true }
            guard dailyUsage > 0 else { return false }
            let days = totalLeft / dailyUsage
            let threshold = Double(medicine.stockThreshold(option: option))
            return days < threshold
        }
        if let remaining = medicine.stockUnitsWithoutTherapy {
            return remaining <= medicine.stockThreshold(option: option)
        }
        return false
    }

    private static func shouldAddDepletedPurchase(
        for medicine: MedicineSnapshot,
        existingItems: [TodayTodoItem],
        option: OptionSnapshot?,
        urgentIds: Set<MedicineId>,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard isOutOfStock(medicine, option: option, recurrenceService: recurrenceService, now: now, calendar: calendar) else {
            return false
        }

        if existingItems.contains(where: { item in
            guard item.category == .purchase else { return false }
            if item.medicineId == medicine.id { return true }
            let itemTitle = normalizedName(item.title)
            let medTitle = normalizedName(medicine.name)
            return itemTitle == medTitle
        }) {
            return false
        }
        return true
    }

    private static func purchaseDetail(
        for medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        urgentIds: Set<MedicineId>,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> String? {
        var parts: [String] = []
        if let status = purchaseStockStatusLabel(
            for: medicine,
            option: option,
            recurrenceService: recurrenceService
        ) {
            parts.append(status)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private static func supplementalTherapyItems(
        medicines: [MedicineSnapshot],
        existingItems: [TodayTodoItem],
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> [TodayTodoItem] {
        var results: [TodayTodoItem] = []
        for medicine in medicines {
            guard isVisibleInToday(medicine) else { continue }
            guard hasPendingIntakeToday(
                for: medicine,
                recurrenceService: recurrenceService,
                now: now,
                calendar: calendar
            ) else { continue }

            if existingItems.contains(where: { item in
                guard item.category == .therapy else { return false }
                if item.medicineId == medicine.id { return true }
                return normalizedName(item.title) == normalizedName(medicine.name)
            }) {
                continue
            }

            let detail: String? = {
                guard let next = earliestDoseToday(
                    for: medicine,
                    recurrenceService: recurrenceService,
                    now: now,
                    calendar: calendar
                ) else { return nil }
                let timeText = timeFormatter.string(from: next)
                return "alle \(timeText)"
            }()

            let name = medicine.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let identifier = "\(name.lowercased())|\(detail?.lowercased() ?? "")"
            let id = "therapy|\(identifier)|\(medicine.latestLogSalt)"
            results.append(
                TodayTodoItem(
                    id: id,
                    title: name,
                    detail: detail,
                    category: .therapy,
                    medicineId: medicine.id
                )
            )
        }
        return results
    }

    private static func isVisibleInToday(_ medicine: MedicineSnapshot) -> Bool {
        if medicine.inCabinet { return true }
        if !medicine.therapies.isEmpty { return true }
        if medicine.hasPackages { return true }
        if medicine.hasMedicinePackages { return true }
        return false
    }

    private static func purchaseStockStatusLabel(
        for medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService
    ) -> String? {
        let threshold = medicine.stockThreshold(option: option)
        if !medicine.therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in medicine.therapies {
                totalLeft += Double(therapy.leftoverUnits)
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
            }
            if totalLeft <= 0 { return "Scorte finite" }
            guard dailyUsage > 0 else { return nil }
            let days = totalLeft / dailyUsage
            return days < Double(threshold) ? "Scorte in esaurimento" : nil
        }
        if let remaining = medicine.stockUnitsWithoutTherapy {
            if remaining <= 0 { return "Scorte finite" }
            return remaining < threshold ? "Scorte in esaurimento" : nil
        }
        return nil
    }

    private static func buildMedicineStatuses(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> [MedicineId: TodayMedicineStatus] {
        var results: [MedicineId: TodayMedicineStatus] = [:]
        results.reserveCapacity(medicines.count)
        for medicine in medicines {
            let needsRx = needsPrescriptionBeforePurchase(
                medicine,
                option: option,
                recurrenceService: recurrenceService,
                now: now,
                calendar: calendar
            )
            let outOfStock = isOutOfStock(
                medicine,
                option: option,
                recurrenceService: recurrenceService,
                now: now,
                calendar: calendar
            )
            let depleted = isStockDepleted(medicine)
            let purchaseStatus = purchaseStockStatusLabel(
                for: medicine,
                option: option,
                recurrenceService: recurrenceService
            )
            let personName = personNameForTherapy(
                medicine,
                option: option,
                recurrenceService: recurrenceService,
                now: now,
                calendar: calendar
            )
            results[medicine.id] = TodayMedicineStatus(
                needsPrescription: needsRx,
                isOutOfStock: outOfStock,
                isDepleted: depleted,
                purchaseStockStatus: purchaseStatus,
                personName: personName
            )
        }
        return results
    }

    private static func buildBlockedTherapyStatuses(
        items: [TodayTodoItem],
        medicineStatuses: [MedicineId: TodayMedicineStatus]
    ) -> [String: TodayBlockedTherapyStatus] {
        var results: [String: TodayBlockedTherapyStatus] = [:]
        for item in items {
            guard item.category == .therapy,
                  let medId = item.medicineId,
                  let status = medicineStatuses[medId]
            else { continue }
            if status.needsPrescription || status.isOutOfStock {
                results[item.id] = TodayBlockedTherapyStatus(
                    medicineId: medId,
                    needsPrescription: status.needsPrescription,
                    isOutOfStock: status.isOutOfStock,
                    isDepleted: status.isDepleted,
                    personName: status.personName
                )
            }
        }
        return results
    }

    private static func isStockDepleted(_ medicine: MedicineSnapshot) -> Bool {
        if !medicine.therapies.isEmpty {
            let totalLeft = medicine.therapies.reduce(0.0) { $0 + Double($1.leftoverUnits) }
            return totalLeft <= 0
        }
        if let remaining = medicine.stockUnitsWithoutTherapy {
            return remaining <= 0
        }
        return false
    }

    private static func personNameForTherapy(
        _ medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> String? {
        if let info = nextDoseTodayInfo(for: medicine, option: option, now: now, calendar: calendar),
           let person = info.personName,
           !person.isEmpty {
            return person
        }
        if let person = medicine.therapies.compactMap({ $0.personName }).first(where: { !$0.isEmpty }) {
            return person
        }
        return nil
    }

    private static func manualIntakeEnabled(
        for medicine: MedicineSnapshot,
        option: OptionSnapshot?,
        therapies: [TherapySnapshot]?
    ) -> Bool {
        if let option { return option.manualIntakeRegistration }
        if medicine.manualIntakeRegistration { return true }
        let list = therapies ?? medicine.therapies
        return list.contains(where: { $0.manualIntakeRegistration })
    }

    private static func scheduledTimesToday(
        for therapy: TherapySnapshot,
        now: Date,
        recurrenceService: RecurrenceService,
        calendar: Calendar
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let allowed = allowedEvents(
            on: today,
            for: therapy,
            recurrenceService: recurrenceService,
            calendar: calendar
        )
        guard allowed > 0 else { return [] }
        guard !therapy.doses.isEmpty else { return [] }
        let sortedDoses = therapy.doses.sorted { $0.time < $1.time }
        let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
        return limitedDoses.compactMap { dose in
            combine(day: today, withTime: dose.time, calendar: calendar)
        }
    }

    private static func allowedEvents(
        on day: Date,
        for therapy: TherapySnapshot,
        recurrenceService: RecurrenceService,
        calendar: Calendar
    ) -> Int {
        let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.startDate ?? day
        let perDay = max(1, therapy.doses.count)
        return recurrenceService.allowedEvents(
            on: day,
            rule: rule,
            startDate: start,
            dosesPerDay: perDay,
            calendar: calendar
        )
    }

    private static func relevantIntakeLogsToday(
        for therapy: TherapySnapshot,
        medicine: MedicineSnapshot,
        now: Date,
        calendar: Calendar
    ) -> [LogEntry] {
        let logsToday = medicine.effectiveIntakeLogs(on: now, calendar: calendar)
        let assigned = logsToday.filter { $0.therapyId == therapy.id }
        if !assigned.isEmpty { return assigned }

        let unassigned = logsToday.filter { $0.therapyId == nil }
        let therapyCount = medicine.therapies.count
        if therapyCount == 1 { return unassigned }
        return unassigned.filter { $0.packageId == therapy.packageId }
    }

    private static func completedDoseCountToday(
        for therapy: TherapySnapshot,
        medicine: MedicineSnapshot,
        now: Date,
        calendar: Calendar,
        scheduledTimes: [Date]
    ) -> Int {
        guard !scheduledTimes.isEmpty else { return 0 }
        let logsToday = relevantIntakeLogsToday(for: therapy, medicine: medicine, now: now, calendar: calendar)
        guard !logsToday.isEmpty else { return 0 }

        let schedule = scheduledTimes.sorted()
        let logTimes = logsToday.map(\.timestamp).sorted()
        var scheduleIndex = schedule.count - 1
        var completed = 0

        for logTime in logTimes.sorted(by: >) {
            while scheduleIndex >= 0, schedule[scheduleIndex] > logTime {
                scheduleIndex -= 1
            }
            if scheduleIndex < 0 { break }
            completed += 1
            scheduleIndex -= 1
        }

        return completed
    }

    private static func hasPendingIntakeToday(
        for medicine: MedicineSnapshot,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard !medicine.therapies.isEmpty else { return false }
        let today = calendar.startOfDay(for: now)

        for therapy in medicine.therapies {
            let allowed = allowedEvents(
                on: today,
                for: therapy,
                recurrenceService: recurrenceService,
                calendar: calendar
            )
            guard allowed > 0 else { continue }

            let timesToday = scheduledTimesToday(
                for: therapy,
                now: now,
                recurrenceService: recurrenceService,
                calendar: calendar
            )
            guard !timesToday.isEmpty else { continue }
            let completedCount = completedDoseCountToday(
                for: therapy,
                medicine: medicine,
                now: now,
                calendar: calendar,
                scheduledTimes: timesToday
            )
            if completedCount < timesToday.count {
                return true
            }
        }

        return false
    }

    private static func nextUpcomingDoseDateConsideringIntake(
        for therapy: TherapySnapshot,
        medicine: MedicineSnapshot,
        now: Date,
        recurrenceService: RecurrenceService,
        calendar: Calendar
    ) -> Date? {
        let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
        let startDate = therapy.startDate ?? now

        let timesToday = scheduledTimesToday(
            for: therapy,
            now: now,
            recurrenceService: recurrenceService,
            calendar: calendar
        )
        if calendar.isDateInToday(now), !timesToday.isEmpty {
            let completedCount = completedDoseCountToday(
                for: therapy,
                medicine: medicine,
                now: now,
                calendar: calendar,
                scheduledTimes: timesToday
            )
            if completedCount >= timesToday.count {
                let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: now)) ?? now
                return recurrenceService.nextOccurrence(
                    rule: rule,
                    startDate: startDate,
                    after: endOfDay,
                    doses: therapy.doses,
                    calendar: calendar
                )
            }
            let pending = Array(timesToday.dropFirst(min(completedCount, timesToday.count)))
            if let firstPending = pending.first {
                return firstPending
            }
        }

        return recurrenceService.nextOccurrence(
            rule: rule,
            startDate: startDate,
            after: now,
            doses: therapy.doses,
            calendar: calendar
        )
    }

    private static func medicine(for item: TodayTodoItem, medicines: [MedicineSnapshot]) -> MedicineSnapshot? {
        if let id = item.medicineId, let medicine = medicines.first(where: { $0.id == id }) {
            return medicine
        }
        let normalizedTitle = normalizedName(item.title)
        return medicines.first { normalizedName($0.name) == normalizedTitle }
    }

    private static func blockedTherapyInfo(
        for item: TodayTodoItem,
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> MedicineSnapshot? {
        guard item.category == .therapy, let med = medicine(for: item, medicines: medicines) else { return nil }
        let needsRx = needsPrescriptionBeforePurchase(med, option: option, recurrenceService: recurrenceService, now: now, calendar: calendar)
        let outOfStock = isOutOfStock(med, option: option, recurrenceService: recurrenceService, now: now, calendar: calendar)
        guard needsRx || outOfStock else { return nil }
        return med
    }

    private static func deadlineTodoItems(from medicines: [MedicineSnapshot]) -> [TodayTodoItem] {
        let candidates: [(MedicineSnapshot, Int, String, Date)] = medicines.compactMap { medicine in
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
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map { medicine, _, label, _ in
                let detail = "Scaduto \(label)"
                let id = "purchase|deadline|\(medicine.externalKey)|\(label)"
                return TodayTodoItem(
                    id: id,
                    title: medicine.name,
                    detail: detail,
                    category: .purchase,
                    medicineId: medicine.id
                )
            }
    }

    private static func filterDueTherapyItems(
        _ items: [TodayTodoItem],
        medicines: [MedicineSnapshot],
        recurrenceService: RecurrenceService,
        now: Date,
        calendar: Calendar
    ) -> [TodayTodoItem] {
        items.filter { item in
            if item.category == .therapy, let med = medicine(for: item, medicines: medicines) {
                return hasPendingIntakeToday(
                    for: med,
                    recurrenceService: recurrenceService,
                    now: now,
                    calendar: calendar
                )
            }
            return true
        }
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

    private static func detailForAction(
        base: String?,
        medicine: MedicineSnapshot?,
        urgentIds: Set<MedicineId>
    ) -> String? {
        var parts: [String] = []
        if let base, !base.isEmpty { parts.append(base) }
        if let med = medicine, !urgentIds.contains(med.id),
           let dose = nextDoseTodayText(for: med) {
            parts.append("Oggi: \(dose)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func nextDoseTodayText(for medicine: MedicineSnapshot) -> String? {
        guard !medicine.therapies.isEmpty else { return nil }
        let recurrenceService = RecurrenceService()
        let now = Date()
        let calendar = Calendar.current
        let upcoming = medicine.therapies.compactMap { therapy -> Date? in
            guard let next = nextUpcomingDoseDate(
                for: therapy,
                medicine: medicine,
                now: now,
                recurrenceService: recurrenceService
            ) else {
                return nil
            }
            return calendar.isDateInToday(next) ? next : nil
        }.sorted().first
        guard let next = upcoming else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: next)
    }

    private static func combine(day: Date, withTime time: Date, calendar: Calendar) -> Date? {
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

    private static func normalizedTimeDetail(from detail: String) -> String? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[0-9]{1,2}:[0-9]{2}$"
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return "alle \(trimmed)"
        }
        return nil
    }

    private static func timeComponents(from detail: String) -> (hour: Int, minute: Int)? {
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

    private static func todoItem(from snapshot: TodoSnapshot) -> TodayTodoItem? {
        guard let category = TodayTodoCategory(rawValue: snapshot.category) else { return nil }
        return TodayTodoItem(
            id: snapshot.sourceId,
            title: snapshot.title,
            detail: snapshot.detail,
            category: category,
            medicineId: snapshot.medicineId
        )
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

extension MedicineSnapshot {
    var latestLogSalt: String {
        guard let lastDate = logs.map(\.timestamp).max() else { return "0" }
        return String(Int(lastDate.timeIntervalSince1970))
    }

    func stockThreshold(option: OptionSnapshot?) -> Int {
        let value = option?.dayThresholdStocksAlarm ?? 0
        return value > 0 ? value : 7
    }

    func effectiveIntakeLogs(calendar: Calendar = .current) -> [LogEntry] {
        effectiveLogs(type: .intake, undoType: .intakeUndo)
    }

    func effectiveIntakeLogs(on date: Date, calendar: Calendar = .current) -> [LogEntry] {
        effectiveIntakeLogs(calendar: calendar).filter { log in
            calendar.isDate(log.timestamp, inSameDayAs: date)
        }
    }

    func effectivePurchaseLogs() -> [LogEntry] {
        effectiveLogs(type: .purchase, undoType: .purchaseUndo)
    }

    func effectivePrescriptionRequestLogs() -> [LogEntry] {
        effectiveLogs(type: .prescriptionRequest, undoType: .prescriptionRequestUndo)
    }

    func effectivePrescriptionReceivedLogs() -> [LogEntry] {
        effectiveLogs(type: .prescriptionReceived, undoType: .prescriptionReceivedUndo)
    }

    func hasNewPrescriptionRequest() -> Bool {
        let prescriptionLogs = effectivePrescriptionRequestLogs()
        guard !prescriptionLogs.isEmpty else { return false }
        guard let lastPrescription = prescriptionLogs.max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        let purchaseLogsAfterPrescription = effectivePurchaseLogs().filter { $0.timestamp > lastPrescription.timestamp }
        return purchaseLogsAfterPrescription.isEmpty
    }

    func hasEffectivePrescriptionReceived() -> Bool {
        !effectivePrescriptionReceivedLogs().isEmpty
    }

    private func effectiveLogs(type: LogType, undoType: LogType) -> [LogEntry] {
        guard !logs.isEmpty else { return [] }
        let reversed = reversedOperationIds(for: undoType)
        return logs.filter { log in
            guard log.type == type else { return false }
            guard let opId = log.operationId else { return true }
            return !reversed.contains(opId)
        }
    }

    private func reversedOperationIds(for undoType: LogType) -> Set<UUID> {
        Set(
            logs.compactMap { log in
                guard log.type == undoType, let opId = log.reversalOfOperationId else { return nil }
                return opId
            }
        )
    }

    var deadlineMonthYear: (month: Int, year: Int)? {
        guard let month = normalizedDeadlineMonth,
              let year = normalizedDeadlineYear else { return nil }
        return (month, year)
    }

    var deadlineLabel: String? {
        guard let info = deadlineMonthYear else { return nil }
        return String(format: "%02d/%04d", info.month, info.year)
    }

    var deadlineMonthStartDate: Date? {
        guard let info = deadlineMonthYear else { return nil }
        var comps = DateComponents()
        comps.year = info.year
        comps.month = info.month
        comps.day = 1
        return Calendar.current.date(from: comps)
    }

    var monthsUntilDeadline: Int? {
        guard let deadlineStart = deadlineMonthStartDate else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return calendar.dateComponents([.month], from: monthStart, to: deadlineStart).month
    }

    private var normalizedDeadlineMonth: Int? {
        guard let month = deadlineMonth, (1...12).contains(month) else { return nil }
        return month
    }

    private var normalizedDeadlineYear: Int? {
        let yearRange = 2000...2100
        guard let year = deadlineYear, yearRange.contains(year) else { return nil }
        return year
    }
}

private extension TherapySnapshot {
    var doseAmounts: [Double] {
        doses.map { $0.amount }
    }

    var totalDoseUnitsPerDay: Double {
        let sum = doseAmounts.reduce(0, +)
        return sum > 0 ? sum : 0
    }

    func stimaConsumoGiornaliero(recurrenceService: RecurrenceService) -> Double {
        let rruleString = rrule ?? ""
        if rruleString.isEmpty { return 0 }

        let parsedRule = recurrenceService.parseRecurrenceString(rruleString)
        let freq = parsedRule.freq.uppercased()
        let interval = max(1, parsedRule.interval)
        let byDayCount = parsedRule.byDay.count
        let baseDoseUnits = max(1, totalDoseUnitsPerDay)

        switch freq {
        case "DAILY":
            return baseDoseUnits / Double(interval)
        case "WEEKLY":
            let weekly = baseDoseUnits * Double(max(byDayCount, 1))
            return weekly / Double(7 * interval)
        default:
            return 0
        }
    }
}
