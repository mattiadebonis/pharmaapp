import Foundation

// MARK: - Centralized Copy

public struct CabinetSummarySettings {
    public static let defaultImminentDoseWindowMinutes = 60

    public let imminentDoseWindowMinutes: Int

    public init(imminentDoseWindowMinutes: Int = CabinetSummarySettings.defaultImminentDoseWindowMinutes) {
        self.imminentDoseWindowMinutes = max(1, imminentDoseWindowMinutes)
    }
}

enum CabinetSummaryCopy {

    // MARK: Missed dose

    static let missedDoseSingularTitle = "C’è una terapia di oggi che richiede attenzione."
    static func missedDosePluralTitle(count: Int) -> String {
        "Ci sono \(count) terapie di oggi che richiedono attenzione."
    }

    static func missedDoseSubtitle(time: String) -> String {
        "La prima assunzione non completata era alle \(time)."
    }

    // MARK: Imminent dose

    static let imminentDoseTitle = "Tra poco è il momento di una terapia."
    static func imminentDoseCountdownTitle(minutes: Int) -> String {
        "Tra \(minutes) minuti è il momento di una terapia."
    }
    static func imminentDoseSubtitle(time: String) -> String {
        "L’assunzione è alle \(time)."
    }

    // MARK: Refill

    static func refillCountTitle(count: Int) -> String {
        count == 1
            ? "Un farmaco in esaurimento."
            : "\(count) farmaci in esaurimento."
    }

    // MARK: Next dose today

    static let nextDoseTodaySingularTitle = "Oggi c’è ancora una terapia da completare."
    static func nextDoseTodayPluralTitle(count: Int) -> String {
        "Oggi restano \(count) terapie da completare."
    }
    static func nextDoseTodaySubtitle(time: String) -> String {
        "La prossima assunzione è alle \(time)."
    }
    static let nextDoseTodaySubtitleFallback = "Le terapie di oggi sono monitorate."

    // MARK: All under control

    static let allUnderControlTitle = "Per ora non ci sono azioni da fare."
    static let allUnderControlSubtitle = "Tutto sotto controllo e le scorte sono sufficienti."

    // MARK: Inline actions

    static func inlineMissedDose(time: String, medicine: String) -> String {
        "\(time) dose saltata: \(medicine)"
    }
    static func inlineRefillBeforeNextDose(time: String, medicine: String) -> String {
        "\(time) rifornisci \(medicine)"
    }
    static func inlineRefill(medicine: String) -> String {
        "Rifornisci \(medicine)"
    }
    static func inlineRefillWithinToday(medicine: String) -> String {
        "Oggi rifornisci \(medicine)"
    }
    static func inlineNextDose(time: String, medicine: String) -> String {
        "\(time) prendi \(medicine)"
    }
    static func inlineNextDoseFallback(medicine: String) -> String {
        "Prendi \(medicine)"
    }
    static let inlineAllUnderControl = "Per ora nessuna azione"
}

// MARK: - CabinetSummaryPresenter

struct CabinetSummaryPresenter {

    static let imminentDoseWindowMinutes = CabinetSummarySettings.defaultImminentDoseWindowMinutes

    private let calendar: Calendar
    private let settings: CabinetSummarySettings

    init(
        calendar: Calendar = .current,
        settings: CabinetSummarySettings = CabinetSummarySettings()
    ) {
        self.calendar = calendar
        self.settings = settings
    }

    // MARK: - Summary Resolution

    func resolveSummary(from a: AggregatedAnalysis, pharmacy: PharmacyInfo?) -> CabinetSummary {

        // 1. Missed dose
        if a.totalMissedDoseCount > 0, let missedTime = a.earliestMissedDoseTime {
            let time = formatTime(missedTime)
            let title = a.totalMissedDoseCount == 1
                ? CabinetSummaryCopy.missedDoseSingularTitle
                : CabinetSummaryCopy.missedDosePluralTitle(count: a.totalMissedDoseCount)
            return CabinetSummary(
                title: title,
                subtitle: CabinetSummaryCopy.missedDoseSubtitle(time: time),
                state: .critical,
                priority: .missedDose
            )
        }

        // 2. Imminent dose (within configured window)
        if let imminentTime = a.imminentDoseTime,
           a.imminentDoseMinutesAway.map({ $0 <= settings.imminentDoseWindowMinutes }) ?? true {
            let title: String
            if let minutesAway = a.imminentDoseMinutesAway {
                title = CabinetSummaryCopy.imminentDoseCountdownTitle(minutes: minutesAway)
            } else {
                title = CabinetSummaryCopy.imminentDoseTitle
            }
            return CabinetSummary(
                title: title,
                subtitle: CabinetSummaryCopy.imminentDoseSubtitle(time: formatTime(imminentTime)),
                state: .warning,
                priority: .imminentDose
            )
        }

        // 3. Refill before next dose (critical)
        if a.refillBeforeNextDoseCount > 0 {
            return CabinetSummary(
                title: CabinetSummaryCopy.refillCountTitle(count: a.refillBeforeNextDoseCount),
                subtitle: refillSubtitle(pharmacy: pharmacy),
                state: .critical,
                priority: .refillBeforeNextDose
            )
        }

        // 4. Refill within today
        if a.refillWithinTodayCount > 0 {
            return CabinetSummary(
                title: CabinetSummaryCopy.refillCountTitle(count: a.refillWithinTodayCount),
                subtitle: refillSubtitle(pharmacy: pharmacy),
                state: .warning,
                priority: .refillWithinToday
            )
        }

        // 5. Refill soon
        if a.refillSoonCount > 0 {
            return CabinetSummary(
                title: CabinetSummaryCopy.refillCountTitle(count: a.refillSoonCount),
                subtitle: refillSubtitle(pharmacy: pharmacy),
                state: .info,
                priority: .refillSoon
            )
        }

        // 6. Next dose today
        if a.totalPendingDoseCount > 0 {
            let n = a.totalPendingDoseCount
            let title = n == 1
                ? CabinetSummaryCopy.nextDoseTodaySingularTitle
                : CabinetSummaryCopy.nextDoseTodayPluralTitle(count: n)
            let subtitle = a.nextUpcomingDoseTime
                .map { CabinetSummaryCopy.nextDoseTodaySubtitle(time: formatTime($0)) }
                ?? CabinetSummaryCopy.nextDoseTodaySubtitleFallback
            return CabinetSummary(
                title: title,
                subtitle: subtitle,
                state: .info,
                priority: .nextDoseToday
            )
        }

        // 7. All under control
        return .allUnderControl
    }

    // MARK: - Inline Action Resolution

    func resolveInlineAction(from a: AggregatedAnalysis) -> CabinetInlineAction {
        if let candidate = a.missedDoseCandidate {
            return CabinetInlineAction(
                text: CabinetSummaryCopy.inlineMissedDose(
                    time: formatTime(candidate.time),
                    medicine: candidate.medicineName
                ),
                priority: .missedDose
            )
        }

        if a.imminentDoseTime != nil, let candidate = a.nextDoseCandidate {
            return CabinetInlineAction(
                text: CabinetSummaryCopy.inlineNextDose(
                    time: formatTime(candidate.time),
                    medicine: candidate.medicineName
                ),
                priority: .imminentDose
            )
        }

        if let candidate = a.refillBeforeNextDoseCandidate {
            let text: String
            if let time = candidate.nextDoseTime {
                text = CabinetSummaryCopy.inlineRefillBeforeNextDose(
                    time: formatTime(time),
                    medicine: candidate.medicineName
                )
            } else {
                text = CabinetSummaryCopy.inlineRefill(medicine: candidate.medicineName)
            }
            return CabinetInlineAction(text: text, priority: .refillBeforeNextDose)
        }

        if let candidate = a.refillWithinTodayCandidate {
            return CabinetInlineAction(
                text: CabinetSummaryCopy.inlineRefillWithinToday(medicine: candidate.medicineName),
                priority: .refillWithinToday
            )
        }

        if let candidate = a.refillSoonCandidate {
            return CabinetInlineAction(
                text: CabinetSummaryCopy.inlineRefill(medicine: candidate.medicineName),
                priority: .refillSoon
            )
        }

        if let candidate = a.nextDoseCandidate {
            return CabinetInlineAction(
                text: CabinetSummaryCopy.inlineNextDose(
                    time: formatTime(candidate.time),
                    medicine: candidate.medicineName
                ),
                priority: .nextDoseToday
            )
        }

        return .allUnderControl
    }

    // MARK: - Formatting Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func refillSubtitle(pharmacy: PharmacyInfo?) -> String {
        pharmacySuggestion(from: pharmacy) ?? ""
    }

    private func pharmacySuggestion(from pharmacy: PharmacyInfo?) -> String? {
        let name = pharmacy?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false) ? name : nil

        let distance = pharmacy?.distanceText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " · ", with: " o ")
        let resolvedDistance = (distance?.isEmpty == false) ? distance : nil

        let status = pharmacy?.isOpen.map { $0 ? "aperta" : "chiusa" }

        guard resolvedName != nil || resolvedDistance != nil || status != nil else { return nil }

        if let resolvedName {
            let detailParts = [status, resolvedDistance.map { "a \($0)" }].compactMap { $0 }
            if detailParts.isEmpty {
                return "Farmacia suggerita: \(resolvedName)."
            }
            return "Farmacia suggerita: \(resolvedName), \(detailParts.joined(separator: " "))."
        }

        if let status, let resolvedDistance {
            return "Farmacia suggerita: \(status) a \(resolvedDistance)."
        }
        if let status {
            return "Farmacia suggerita: \(status)."
        }
        if let resolvedDistance {
            return "Farmacia suggerita: a \(resolvedDistance)."
        }

        return nil
    }
}
