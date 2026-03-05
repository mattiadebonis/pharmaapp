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

    // MARK: Refill before next dose

    static let refillBeforeNextDoseTitle = "Serve un rifornimento prima della prossima terapia."
    static func refillBeforeNextDoseSubtitle(time: String) -> String {
        "La prossima assunzione è alle \(time)."
    }
    static let refillBeforeNextDoseSubtitleFallback = "La prossima assunzione è prevista a breve."

    // MARK: Refill within today

    static let refillWithinTodayTitle = "Oggi conviene organizzare un rifornimento."
    static func refillWithinTodaySubtitle(count: Int) -> String {
        count == 1
            ? "1 farmaco va rifornito entro oggi."
            : "\(count) farmaci vanno riforniti entro oggi."
    }

    // MARK: Refill soon

    static let refillSoonTitle = "A breve sarà utile fare un rifornimento."
    static func refillSoonSubtitle(count: Int) -> String {
        count == 1
            ? "1 farmaco richiede rifornimento."
            : "\(count) farmaci richiedono rifornimento."
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
    static let allUnderControlSubtitle = "Le terapie sono coperte e le scorte sono adeguate."

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
            let subtitle: String
            if let nextTime = a.refillBeforeNextDoseCandidate?.nextDoseTime {
                subtitle = CabinetSummaryCopy.refillBeforeNextDoseSubtitle(time: formatTime(nextTime))
            } else {
                subtitle = CabinetSummaryCopy.refillBeforeNextDoseSubtitleFallback
            }
            return CabinetSummary(
                title: CabinetSummaryCopy.refillBeforeNextDoseTitle,
                subtitle: appendPharmacySuggestion(to: subtitle, pharmacy: pharmacy),
                state: .critical,
                priority: .refillBeforeNextDose
            )
        }

        // 4. Refill within today
        if a.refillWithinTodayCount > 0 {
            let n = a.refillWithinTodayCount
            let subtitle = CabinetSummaryCopy.refillWithinTodaySubtitle(count: n)
            return CabinetSummary(
                title: CabinetSummaryCopy.refillWithinTodayTitle,
                subtitle: appendPharmacySuggestion(to: subtitle, pharmacy: pharmacy),
                state: .warning,
                priority: .refillWithinToday
            )
        }

        // 5. Refill soon
        if a.refillSoonCount > 0 {
            let n = a.refillSoonCount
            let subtitle = CabinetSummaryCopy.refillSoonSubtitle(count: n)
            return CabinetSummary(
                title: CabinetSummaryCopy.refillSoonTitle,
                subtitle: appendPharmacySuggestion(to: subtitle, pharmacy: pharmacy),
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

    private func appendPharmacySuggestion(to subtitle: String, pharmacy: PharmacyInfo?) -> String {
        guard let suggestion = pharmacySuggestion(from: pharmacy) else { return subtitle }
        return "\(subtitle) \(suggestion)"
    }

    private func pharmacySuggestion(from pharmacy: PharmacyInfo?) -> String? {
        guard let text = pharmacy?.distanceText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else { return nil }
        let normalized = text.replacingOccurrences(of: " · ", with: " o ")
        return "La farmacia più vicina è a \(normalized)."
    }
}
