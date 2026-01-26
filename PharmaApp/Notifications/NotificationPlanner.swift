import Foundation
import CoreData

struct NotificationScheduleConfiguration {
    var therapyHorizonDays: Int = 14
    var maxTherapyNotifications: Int = 48
    var maxStockNotifications: Int = 12
    var maxTotalNotifications: Int = 60
    var stockNotificationHour: Int = 9
    var stockNotificationMinute: Int = 0
    var stockAlertCooldownHours: Int = 24
    var stockForecastHorizonDays: Int = 90
    var therapyGraceWindowSeconds: Int = 90
}

enum NotificationPlanOrigin: String {
    case immediate
    case scheduled
}

enum NotificationPlanKind: String {
    case therapy
    case stockLow
    case stockOut
}

struct NotificationPlanItem: Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
    let kind: NotificationPlanKind
    let origin: NotificationPlanOrigin
    let userInfo: [String: String]
}

struct NotificationPlan {
    let therapy: [NotificationPlanItem]
    let stock: [NotificationPlanItem]
}

enum StockAlertLevel: String, Codable {
    case none
    case low
    case empty
}

struct StockAlertState: Codable, Equatable {
    let level: StockAlertLevel
    let lastNotifiedAt: Date
}

protocol StockAlertStateStore {
    func state(for medicineId: UUID) -> StockAlertState?
    func setState(_ state: StockAlertState, for medicineId: UUID)
    func clearState(for medicineId: UUID)
}

final class UserDefaultsStockAlertStateStore: StockAlertStateStore {
    private let defaults: UserDefaults
    private let storageKey = "stock.alert.state.v1"
    private var cache: [String: StockAlertState] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadCache()
    }

    func state(for medicineId: UUID) -> StockAlertState? {
        cache[medicineId.uuidString]
    }

    func setState(_ state: StockAlertState, for medicineId: UUID) {
        cache[medicineId.uuidString] = state
        persist()
    }

    func clearState(for medicineId: UUID) {
        cache.removeValue(forKey: medicineId.uuidString)
        persist()
    }

    private func loadCache() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            cache = try JSONDecoder().decode([String: StockAlertState].self, from: data)
        } catch {
            cache = [:]
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(cache)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Ignore persistence errors to avoid impacting the main flow.
        }
    }
}

struct NotificationPlanner {
    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private let config: NotificationScheduleConfiguration
    private let stockAlertStore: StockAlertStateStore

    init(
        context: NSManagedObjectContext,
        calendar: Calendar = .current,
        config: NotificationScheduleConfiguration = NotificationScheduleConfiguration(),
        stockAlertStore: StockAlertStateStore = UserDefaultsStockAlertStateStore()
    ) {
        self.context = context
        self.calendar = calendar
        self.config = config
        self.stockAlertStore = stockAlertStore
    }

    func plan(now: Date = Date()) -> NotificationPlan {
        let therapies = fetchTherapies()
        let medicines = fetchMedicines()
        return NotificationPlan(
            therapy: planTherapyNotifications(therapies: therapies, now: now),
            stock: planStockNotifications(medicines: medicines, now: now)
        )
    }

    func planTherapyNotifications(therapies: [Therapy], now: Date) -> [NotificationPlanItem] {
        guard !therapies.isEmpty else { return [] }
        guard let endDate = calendar.date(byAdding: .day, value: config.therapyHorizonDays, to: now) else {
            return []
        }

        let generator = DoseEventGenerator(context: context, calendar: calendar)
        let events = generator.generateEvents(therapies: therapies, from: now, to: endDate)
        guard !events.isEmpty else { return [] }

        let therapyLookup = Dictionary(uniqueKeysWithValues: therapies.map { ($0.objectID, $0) })
        var items: [NotificationPlanItem] = []

        let graceWindow = Double(config.therapyGraceWindowSeconds)
        for event in events {
            let delta = event.date.timeIntervalSince(now)
            if delta < 0, abs(delta) > graceWindow { continue }
            guard let therapy = therapyLookup[event.therapyId] else { continue }
            let medicine = therapy.medicine
            let title = "È ora della terapia"
            let personLabel = personLabel(for: therapy)
            let body = personLabel.isEmpty
                ? "Assumi \(medicine.nome)"
                : "Assumi \(medicine.nome) per \(personLabel)"
            let id = "therapy-\(UUID().uuidString)"
            let userInfo = [
                "type": NotificationPlanKind.therapy.rawValue,
                "therapyId": therapy.objectID.uriRepresentation().absoluteString,
                "medicineId": medicine.id.uuidString
            ]
            let origin: NotificationPlanOrigin = delta <= 0 ? .immediate : .scheduled
            let itemDate = delta <= 0 ? now : event.date
            items.append(
                NotificationPlanItem(
                    id: id,
                    date: itemDate,
                    title: title,
                    body: body,
                    kind: .therapy,
                    origin: origin,
                    userInfo: userInfo
                )
            )
        }

        return Array(items.sorted { $0.date < $1.date }.prefix(config.maxTherapyNotifications))
    }

    func planStockNotifications(medicines: [Medicine], now: Date) -> [NotificationPlanItem] {
        guard !medicines.isEmpty else { return [] }
        let recurrenceManager = RecurrenceManager(context: context)
        let maxForecast = Double(config.stockForecastHorizonDays)

        var items: [NotificationPlanItem] = []

        for medicine in medicines {
            let evaluation = evaluateStock(for: medicine, recurrenceManager: recurrenceManager)
            let currentLevel = evaluation.level

            if currentLevel == .none {
                stockAlertStore.clearState(for: medicine.id)
            }

            if currentLevel == .low || currentLevel == .empty {
                if shouldNotifyNow(level: currentLevel, medicineId: medicine.id, now: now) {
                    let title = currentLevel == .empty ? "Scorte finite" : "Scorte basse"
                    let body = currentLevel == .empty
                        ? "Scorte terminate per \(medicine.nome)"
                        : "Le scorte di \(medicine.nome) stanno finendo"
                    let kind: NotificationPlanKind = currentLevel == .empty ? .stockOut : .stockLow
                    let id = "stock-\(currentLevel.rawValue)-\(UUID().uuidString)"
                    let userInfo = [
                        "type": kind.rawValue,
                        "medicineId": medicine.id.uuidString
                    ]
                    items.append(
                        NotificationPlanItem(
                            id: id,
                            date: now.addingTimeInterval(1),
                            title: title,
                            body: body,
                            kind: kind,
                            origin: .immediate,
                            userInfo: userInfo
                        )
                    )
                    stockAlertStore.setState(
                        StockAlertState(level: currentLevel, lastNotifiedAt: now),
                        for: medicine.id
                    )
                }
            }

            guard let coverageDays = evaluation.coverageDays, coverageDays > 0 else {
                continue
            }

            if coverageDays > maxForecast { continue }

            if currentLevel == .none {
                let lowDelta = coverageDays - Double(evaluation.threshold)
                if lowDelta > 0, let lowDate = forecastDate(afterDays: lowDelta, now: now) {
                    let id = "stock-low-\(UUID().uuidString)"
                    let userInfo = [
                        "type": NotificationPlanKind.stockLow.rawValue,
                        "medicineId": medicine.id.uuidString
                    ]
                    items.append(
                        NotificationPlanItem(
                            id: id,
                            date: lowDate,
                            title: "Scorte basse",
                            body: "Le scorte di \(medicine.nome) stanno per finire",
                            kind: .stockLow,
                            origin: .scheduled,
                            userInfo: userInfo
                        )
                    )
                }
            }

            if currentLevel != .empty {
                if let outDate = forecastDate(afterDays: coverageDays, now: now) {
                    let id = "stock-out-\(UUID().uuidString)"
                    let userInfo = [
                        "type": NotificationPlanKind.stockOut.rawValue,
                        "medicineId": medicine.id.uuidString
                    ]
                    items.append(
                        NotificationPlanItem(
                            id: id,
                            date: outDate,
                            title: "Scorte finite",
                            body: "Le scorte di \(medicine.nome) stanno terminando",
                            kind: .stockOut,
                            origin: .scheduled,
                            userInfo: userInfo
                        )
                    )
                }
            }
        }

        let sorted = items.sorted { $0.date < $1.date }
        return Array(sorted.prefix(config.maxStockNotifications))
    }

    private func fetchTherapies() -> [Therapy] {
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        do {
            let therapies = try context.fetch(request)
            return therapies.filter { therapy in
                guard let rrule = therapy.rrule, !rrule.isEmpty else { return false }
                guard let doses = therapy.doses, !doses.isEmpty else { return false }
                return true
            }
        } catch {
            return []
        }
    }

    private func fetchMedicines() -> [Medicine] {
        let request: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        do {
            return try context.fetch(request)
        } catch {
            return []
        }
    }

    private func personLabel(for therapy: Therapy) -> String {
        let name = therapy.person.nome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let surname = therapy.person.cognome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = "\(name) \(surname)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined
    }

    private func shouldNotifyNow(level: StockAlertLevel, medicineId: UUID, now: Date) -> Bool {
        guard level == .low || level == .empty else { return false }
        guard let state = stockAlertStore.state(for: medicineId) else {
            return true
        }
        if state.level != level {
            return true
        }
        let cooldown = Double(config.stockAlertCooldownHours) * 3600
        return now.timeIntervalSince(state.lastNotifiedAt) >= cooldown
    }

    private func forecastDate(afterDays days: Double, now: Date) -> Date? {
        guard days > 0 else { return nil }
        let roundedDays = Int(ceil(days))
        guard roundedDays >= 0 else { return nil }
        guard let targetDay = calendar.date(byAdding: .day, value: roundedDays, to: calendar.startOfDay(for: now)) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
        components.hour = config.stockNotificationHour
        components.minute = config.stockNotificationMinute
        guard var date = calendar.date(from: components) else {
            return nil
        }
        if date <= now, let adjusted = calendar.date(byAdding: .day, value: 1, to: date) {
            date = adjusted
        }
        return date
    }

    private func evaluateStock(
        for medicine: Medicine,
        recurrenceManager: RecurrenceManager
    ) -> StockEvaluation {
        let threshold = medicine.stockThreshold(option: nil)
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            for therapy in therapies {
                totalLeftover += Double(therapy.leftover())
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalDailyUsage <= 0 {
                return StockEvaluation(level: .none, coverageDays: nil, remainingUnits: Int(totalLeftover), threshold: threshold)
            }
            let coverage = totalLeftover / totalDailyUsage
            if coverage <= 0 {
                return StockEvaluation(level: .empty, coverageDays: 0, remainingUnits: Int(totalLeftover), threshold: threshold)
            }
            if coverage < Double(threshold) {
                return StockEvaluation(level: .low, coverageDays: coverage, remainingUnits: Int(totalLeftover), threshold: threshold)
            }
            return StockEvaluation(level: .none, coverageDays: coverage, remainingUnits: Int(totalLeftover), threshold: threshold)
        }

        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            if remaining <= 0 {
                return StockEvaluation(level: .empty, coverageDays: nil, remainingUnits: remaining, threshold: threshold)
            }
            if remaining < threshold {
                return StockEvaluation(level: .low, coverageDays: nil, remainingUnits: remaining, threshold: threshold)
            }
            return StockEvaluation(level: .none, coverageDays: nil, remainingUnits: remaining, threshold: threshold)
        }

        return StockEvaluation(level: .none, coverageDays: nil, remainingUnits: nil, threshold: threshold)
    }
}

struct StockEvaluation {
    let level: StockAlertLevel
    let coverageDays: Double?
    let remainingUnits: Int?
    let threshold: Int
}
