import Foundation

public struct PharmacyInfo {
    public let name: String?
    public let isOpen: Bool?
    public let distanceText: String?

    public init(name: String?, isOpen: Bool?, distanceText: String?) {
        self.name = name
        self.isOpen = isOpen
        self.distanceText = distanceText
    }
}

public struct CabinetSummaryReadModel {
    private let recurrenceService: RecurrencePort
    private let calendar: Calendar

    public init(recurrenceService: RecurrencePort, calendar: Calendar = .current) {
        self.recurrenceService = recurrenceService
        self.calendar = calendar
    }

    public func buildLines(
        medicines: [MedicineSnapshot],
        option: OptionSnapshot?,
        pharmacy: PharmacyInfo?,
        now: Date = Date()
    ) -> [String] {
        guard let option else {
            return ["Tutto sotto controllo!"]
        }

        let lowStock = medicines.filter { isLowStock($0, option: option) }
        let depletedStock = lowStock.filter { autonomyDays(for: $0) == 0 }
        let oneDayStock = lowStock.filter { autonomyDays(for: $0) == 1 }
        let missedSummary = missedDoseSummary(for: medicines, now: now)
        let todayTherapyNames = medicinesWithTherapyToday(medicines: medicines, now: now)

        let stockOk = lowStock.isEmpty
        let therapyOk = missedSummary.medicines.isEmpty
        if stockOk && therapyOk && todayTherapyNames.isEmpty {
            return ["Tutto sotto controllo!"]
        }

        var lines: [String] = []

        if !todayTherapyNames.isEmpty {
            let names = todayTherapyNames.joined(separator: ", ")
            if todayTherapyNames.count == 1 {
                lines.append("Oggi in terapia con \(names)")
            } else {
                lines.append("Oggi in terapia con \(names)")
            }
        }

        if stockOk {
            if !todayTherapyNames.isEmpty {
                lines.append("Scorte a posto")
            }
        } else if !depletedStock.isEmpty {
            let subject = medicineNamesDescription(for: depletedStock)
            let verb = depletedStock.count == 1 ? "ha" : "hanno"
            lines.append("\(subject) \(verb) le scorte terminate")
        } else if !oneDayStock.isEmpty {
            let subject = medicineNamesDescription(for: oneDayStock)
            lines.append("A \(subject) manca solo un giorno di autonomia")
        } else {
            lines.append(refillLine(for: lowStock, pharmacy: pharmacy))
        }

        if !therapyOk {
            lines.append(missedSummaryLine(for: missedSummary))
        }

        return lines
    }

    private func isLowStock(_ medicine: MedicineSnapshot, option: OptionSnapshot) -> Bool {
        if let autonomyDays = autonomyDays(for: medicine) {
            return autonomyDays < medicine.stockThreshold(option: option)
        }

        if let remainingUnits = medicine.stockUnitsWithoutTherapy {
            return remainingUnits < medicine.stockThreshold(option: option)
        }

        return false
    }

    private func autonomyDays(for medicine: MedicineSnapshot) -> Int? {
        guard !medicine.therapies.isEmpty else { return nil }

        var totalLeftover: Double = 0
        var totalDaily: Double = 0
        for therapy in medicine.therapies {
            totalLeftover += Double(therapy.leftoverUnits)
            totalDaily += therapy.stimaConsumoGiornaliero(recurrenceService: recurrenceService)
        }

        if totalLeftover <= 0 { return 0 }
        guard totalDaily > 0 else { return nil }

        return max(0, Int(floor(totalLeftover / totalDaily)))
    }

    private func refillLine(for medicines: [MedicineSnapshot], pharmacy: PharmacyInfo?) -> String {
        let subject = medicineNamesDescription(for: medicines)
        let verb = medicines.count == 1 ? "è" : "sono"
        let pronoun = medicines.count == 1 ? "rifornirlo" : "rifornirli"
        guard let pharmacyDescription = pharmacyDescription(from: pharmacy) else {
            return "\(subject) \(verb) in esaurimento"
        }
        return "\(subject) \(verb) in esaurimento e puoi \(pronoun) presso \(pharmacyDescription)"
    }

    private func pharmacyDescription(from pharmacy: PharmacyInfo?) -> String? {
        guard let resolvedName = pharmacy?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !resolvedName.isEmpty else {
            return nil
        }

        guard let detail = pharmacyDetail(from: pharmacy) else {
            return resolvedName
        }
        return "\(resolvedName), \(detail)"
    }

    private func pharmacyDetail(from pharmacy: PharmacyInfo?) -> String? {
        let status = pharmacy?.isOpen.map { $0 ? "aperta" : "chiusa" }
        let distance: String? = {
            guard let text = pharmacy?.distanceText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty else { return nil }
            return text.replacingOccurrences(of: " · ", with: " o ")
        }()

        switch (status, distance) {
        case let (.some(status), .some(distance)):
            return "\(status) a \(distance)"
        case let (.some(status), .none):
            return status
        case let (.none, .some(distance)):
            return "a \(distance)"
        case (.none, .none):
            return nil
        }
    }

    private struct MissedDoseSummary {
        let medicines: [MedicineSnapshot]
        let doseCount: Int
    }

    private func missedDoseSummary(for medicines: [MedicineSnapshot], now: Date) -> MissedDoseSummary {
        let doseSchedule = DoseScheduleReadModel(recurrenceService: recurrenceService, calendar: calendar)
        var missedMedicines: [MedicineSnapshot] = []
        var doseCount = 0

        for medicine in medicines {
            let manualTherapies = medicine.therapies.filter {
                $0.manualIntakeRegistration || medicine.manualIntakeRegistration
            }
            guard !manualTherapies.isEmpty else { continue }

            var missedCount = 0
            for therapy in manualTherapies {
                let schedule = doseSchedule.baseScheduledTimes(on: now, for: therapy)
                let intakeLogs = medicine.effectiveIntakeLogs(on: now, calendar: calendar)
                let therapyLogs = intakeLogs.filter { $0.therapyId == therapy.id || $0.therapyId == nil }

                let completedBuckets = self.completedBuckets(schedule: schedule, intakeLogs: therapyLogs, on: now)
                let pending = schedule.filter { !completedBuckets.contains(minuteBucket(for: $0)) }
                missedCount += pending.filter { $0 <= now }.count
            }

            guard missedCount > 0 else { continue }
            missedMedicines.append(medicine)
            doseCount += missedCount
        }

        return MissedDoseSummary(medicines: missedMedicines, doseCount: doseCount)
    }

    private func completedBuckets(schedule: [Date], intakeLogs: [LogEntry], on day: Date) -> Set<Int> {
        guard !schedule.isEmpty else { return [] }

        let explicitBuckets = Set(
            intakeLogs
                .compactMap(\.scheduledDueAt)
                .filter { calendar.isDate($0, inSameDayAs: day) }
                .map(minuteBucket(for:))
        )

        var completedBuckets = explicitBuckets
        var remaining = schedule.filter { !explicitBuckets.contains(minuteBucket(for: $0)) }
        let genericLogs = intakeLogs
            .filter { $0.scheduledDueAt == nil }
            .sorted { $0.timestamp < $1.timestamp }

        for log in genericLogs {
            guard let index = remaining.lastIndex(where: { $0 <= log.timestamp }) else { continue }
            completedBuckets.insert(minuteBucket(for: remaining.remove(at: index)))
        }

        return completedBuckets
    }

    private func missedSummaryLine(for summary: MissedDoseSummary) -> String {
        let medicinePart = medicineNamesDescription(for: summary.medicines)
        let verb = summary.medicines.count == 1 ? "ha" : "hanno"
        let dosePart = summary.doseCount == 1
            ? "1 dose saltata"
            : "\(summary.doseCount) dosi saltate"
        return "\(medicinePart) \(verb) \(dosePart)"
    }

    private func medicineNamesDescription(for medicines: [MedicineSnapshot]) -> String {
        var seen = Set<String>()
        let names = medicines.compactMap { medicine -> String? in
            let name = medicine.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return name.localizedCapitalized
        }

        guard !names.isEmpty else {
            return medicines.count == 1 ? "1 medicinale" : "\(medicines.count) medicinali"
        }

        if names.count == 1 { return names[0] }
        if names.count == 2 { return "\(names[0]) e \(names[1])" }

        let head = names.dropLast().joined(separator: ", ")
        return "\(head) e \(names[names.count - 1])"
    }

    private func medicinesWithTherapyToday(medicines: [MedicineSnapshot], now: Date) -> [String] {
        let doseSchedule = DoseScheduleReadModel(recurrenceService: recurrenceService, calendar: calendar)
        var seen = Set<String>()
        var names: [String] = []

        for medicine in medicines {
            guard !medicine.therapies.isEmpty else { continue }
            let hasTherapyToday = medicine.therapies.contains { therapy in
                !doseSchedule.baseScheduledTimes(on: now, for: therapy).isEmpty
            }
            guard hasTherapyToday else { continue }
            let name = medicine.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            names.append(name.localizedCapitalized)
        }

        return names
    }

    private func minuteBucket(for date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }
}
