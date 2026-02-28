import Foundation

struct CabinetSummaryPharmacyInfo {
    let name: String?
    let isOpen: Bool?
    let distanceText: String?
}

struct CabinetSummaryBuilder {
    private struct MissedDoseSummary {
        let medicines: [Medicine]
        let doseCount: Int
    }

    private let recurrenceManager: RecurrenceManager
    private let calendar: Calendar

    init(
        recurrenceManager: RecurrenceManager,
        calendar: Calendar = .current
    ) {
        self.recurrenceManager = recurrenceManager
        self.calendar = calendar
    }

    func buildLines(
        medicines: [Medicine],
        option: Option?,
        pharmacy: CabinetSummaryPharmacyInfo?,
        now: Date = Date()
    ) -> [String] {
        guard let option else {
            return ["Tutto sotto controllo"]
        }

        let lowStock = medicines.filter { isLowStock($0, option: option) }
        let missedSummary = missedDoseSummary(for: medicines, now: now)

        let stockOk = lowStock.isEmpty
        let therapyOk = missedSummary.medicines.isEmpty
        if stockOk && therapyOk {
            return ["Tutto sotto controllo"]
        }

        var lines: [String] = []

        if stockOk {
            lines.append("Scorte a posto")
        } else {
            lines.append(refillLine(for: lowStock, pharmacy: pharmacy))
        }

        if therapyOk {
            lines.append("Terapie in regola")
        } else {
            lines.append(missedSummaryLine(for: missedSummary))
        }

        return lines
    }

    func isLowStock(_ medicine: Medicine, option: Option) -> Bool {
        if let autonomyDays = autonomyDays(for: medicine) {
            return autonomyDays < medicine.stockThreshold(option: option)
        }

        if let remainingUnits = medicine.remainingUnitsWithoutTherapy() {
            return remainingUnits < medicine.stockThreshold(option: option)
        }

        return false
    }

    private func refillLine(for medicines: [Medicine], pharmacy: CabinetSummaryPharmacyInfo?) -> String {
        let subject = medicineNamesDescription(for: medicines)
        let verb = medicines.count == 1 ? "è" : "sono"
        let pronoun = medicines.count == 1 ? "rifornirlo" : "rifornirli"
        guard let pharmacyDescription = pharmacyDescription(from: pharmacy) else {
            return "\(subject) \(verb) in esaurimento"
        }
        return "\(subject) \(verb) in esaurimento e puoi \(pronoun) presso \(pharmacyDescription)"
    }

    private func autonomyDays(for medicine: Medicine) -> Int? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }

        var totalLeftover: Double = 0
        var totalDaily: Double = 0
        for therapy in therapies {
            totalLeftover += Double(therapy.leftover())
            totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        }

        if totalLeftover <= 0 {
            return 0
        }
        guard totalDaily > 0 else { return nil }

        return max(0, Int(floor(totalLeftover / totalDaily)))
    }

    private func pharmacyDescription(from pharmacy: CabinetSummaryPharmacyInfo?) -> String? {
        guard let resolvedName = pharmacy?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty else {
            return nil
        }

        guard let detail = pharmacyDetail(from: pharmacy) else {
            return resolvedName
        }
        return "\(resolvedName), \(detail)"
    }

    private func pharmacyDetail(from pharmacy: CabinetSummaryPharmacyInfo?) -> String? {
        let status = pharmacy?.isOpen.map { $0 ? "aperta" : "chiusa" }
        let distance = pharmacy?.distanceText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty?
            .replacingOccurrences(of: " · ", with: " o ")

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

    private func missedDoseSummary(for medicines: [Medicine], now: Date) -> MissedDoseSummary {
        var missedMedicines: [Medicine] = []
        var doseCount = 0

        for medicine in medicines {
            let missedCount = missedDoseCount(for: medicine, now: now)
            guard missedCount > 0 else { continue }
            missedMedicines.append(medicine)
            doseCount += missedCount
        }

        return MissedDoseSummary(medicines: missedMedicines, doseCount: doseCount)
    }

    private func missedDoseCount(for medicine: Medicine, now: Date) -> Int {
        let therapies = Set((medicine.therapies ?? []).filter {
            $0.manual_intake_registration || medicine.manual_intake_registration
        })
        guard !therapies.isEmpty else {
            return 0
        }

        let plannedTimes = scheduledTimesToday(for: therapies, now: now)
        guard !plannedTimes.isEmpty else { return 0 }

        let takenCount = medicine.effectiveIntakeLogs(on: now, calendar: calendar).count
        let pendingTimes = plannedTimes.dropFirst(min(takenCount, plannedTimes.count))
        return pendingTimes.filter { $0 <= now }.count
    }

    private func scheduledTimesToday(for therapies: Set<Therapy>, now: Date) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var planned: [Date] = []

        for therapy in therapies {
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? today
            let doses = (therapy.doses ?? []).sorted { $0.time < $1.time }
            let perDay = max(1, doses.count)
            let allowed = recurrenceManager.allowedEvents(
                on: today,
                rule: rule,
                startDate: start,
                dosesPerDay: perDay,
                calendar: calendar
            )
            guard allowed > 0 else { continue }
            guard !doses.isEmpty else { continue }

            let limitedDoses = doses.prefix(min(allowed, doses.count))
            for dose in limitedDoses {
                guard let combined = combine(day: today, withTime: dose.time) else { continue }
                guard combined >= start else { continue }
                planned.append(combined)
            }
        }

        return planned.sorted()
    }

    private func missedSummaryLine(for summary: MissedDoseSummary) -> String {
        let medicinePart = medicineNamesDescription(for: summary.medicines)
        let verb = summary.medicines.count == 1 ? "ha" : "hanno"
        let dosePart = summary.doseCount == 1
            ? "1 dose saltata"
            : "\(summary.doseCount) dosi saltate"
        return "\(medicinePart) \(verb) \(dosePart)"
    }

    private func medicineNamesDescription(for medicines: [Medicine]) -> String {
        var seen = Set<String>()
        let names = medicines.compactMap { medicine -> String? in
            let name = medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let nonEmptyName = name.nonEmpty else { return nil }
            let key = nonEmptyName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return formattedMedicineName(nonEmptyName)
        }

        guard !names.isEmpty else {
            return medicines.count == 1 ? "1 medicinale" : "\(medicines.count) medicinali"
        }

        if names.count == 1 {
            return names[0]
        }

        if names.count == 2 {
            return "\(names[0]) e \(names[1])"
        }

        let head = names.dropLast().joined(separator: ", ")
        return "\(head) e \(names[names.count - 1])"
    }

    private func formattedMedicineName(_ name: String) -> String {
        name.localizedCapitalized
    }

    private func combine(day: Date, withTime time: Date) -> Date? {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)

        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second

        return calendar.date(from: merged)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
