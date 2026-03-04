import Foundation

// MARK: - Centralized Copy

enum CabinetSummaryCopy {

    // MARK: Missed dose

    static let missedDoseTitle = "Una terapia di oggi richiede attenzione."

    static func missedDoseSubtitle(time: String) -> String {
        "La prima assunzione non completata era prevista alle \(time)."
    }
    static func missedDoseSubtitleWithPharmacy(time: String, distance: String) -> String {
        "La prima assunzione non completata era prevista alle \(time); farmacia vicina a \(distance)."
    }

    // MARK: Imminent dose

    static func imminentDoseTitle(minutes: Int) -> String {
        "Prossima assunzione tra \(minutes) minuti."
    }
    static func imminentDoseSubtitle(time: String) -> String {
        "È prevista alle \(time)."
    }

    // MARK: Refill before next dose

    static let refillBeforeNextDoseTitle = "Serve un rifornimento prima della prossima assunzione."
    static func refillBeforeNextDoseTimePart(time: String) -> String {
        "La prossima è prevista alle \(time)"
    }
    static let refillBeforeNextDoseTimePartFallback = "La prossima assunzione è imminente"
    static func refillBeforeNextDoseSubtitle(timePart: String, distancePart: String) -> String {
        "\(timePart)\(distancePart)."
    }
    static func refillBeforeNextDosePluralTitle(count: Int) -> String {
        "\(count) farmaci in terapia oggi necessitano di rifornimento."
    }

    // MARK: Refill within today

    static func refillWithinTodayTitle(count: Int) -> String {
        count == 1
            ? "Per le terapie in corso, 1 farmaco va rifornito entro oggi."
            : "Per le terapie in corso, \(count) farmaci vanno riforniti entro oggi."
    }

    // MARK: Refill soon

    static func refillSoonTitle(count: Int) -> String {
        count == 1
            ? "Le terapie sono coperte, ma 1 farmaco richiede rifornimento a breve."
            : "Le terapie sono coperte, ma \(count) farmaci richiedono rifornimento a breve."
    }

    // MARK: Next dose today

    static func nextDoseTodayTitle(count: Int) -> String {
        count == 1
            ? "Oggi resta 1 assunzione da completare."
            : "Oggi restano \(count) assunzioni da completare."
    }
    static func nextDoseTodaySubtitle(time: String) -> String {
        "La prossima è prevista alle \(time)."
    }

    // MARK: Pharmacy

    static func pharmacyNearby(distance: String) -> String {
        "La farmacia più vicina è a \(distance)."
    }

    // MARK: All under control

    static let allUnderControlTitle = "Tutto sotto controllo."
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
    static let inlineAllUnderControl = "Tutto sotto controllo"
}

// MARK: - CabinetSummaryPresenter

struct CabinetSummaryPresenter {

    static let imminentDoseWindowMinutes = 60

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Summary Resolution

    func resolveSummary(from a: AggregatedAnalysis, pharmacy: PharmacyInfo?) -> CabinetSummary {

        // 1. Missed dose
        if a.totalMissedDoseCount > 0, let missedTime = a.earliestMissedDoseTime {
            let time = formatTime(missedTime)
            let subtitle: String
            if a.hasAnyStockIssue, let distance = pharmacyDistanceText(from: pharmacy) {
                subtitle = CabinetSummaryCopy.missedDoseSubtitleWithPharmacy(time: time, distance: distance)
            } else {
                subtitle = CabinetSummaryCopy.missedDoseSubtitle(time: time)
            }
            return CabinetSummary(
                title: CabinetSummaryCopy.missedDoseTitle,
                subtitle: subtitle,
                state: .critical,
                priority: .missedDose
            )
        }

        // 2. Refill before next dose (critical)
        if a.refillBeforeNextDoseCount > 0 {
            let n = a.refillBeforeNextDoseCount
            if n == 1 {
                let distancePart = pharmacyDistanceText(from: pharmacy).map { "; farmacia vicina a \($0)" } ?? ""
                let timePart: String
                if let nextTime = a.nextScheduledDoseTime {
                    timePart = CabinetSummaryCopy.refillBeforeNextDoseTimePart(time: formatTime(nextTime))
                } else {
                    timePart = CabinetSummaryCopy.refillBeforeNextDoseTimePartFallback
                }
                return CabinetSummary(
                    title: CabinetSummaryCopy.refillBeforeNextDoseTitle,
                    subtitle: CabinetSummaryCopy.refillBeforeNextDoseSubtitle(timePart: timePart, distancePart: distancePart),
                    state: .critical,
                    priority: .refillBeforeNextDose
                )
            } else {
                let pharmacySubtitle = pharmacyDistanceText(from: pharmacy)
                    .map { CabinetSummaryCopy.pharmacyNearby(distance: $0) } ?? ""
                return CabinetSummary(
                    title: CabinetSummaryCopy.refillBeforeNextDosePluralTitle(count: n),
                    subtitle: pharmacySubtitle,
                    state: .critical,
                    priority: .refillBeforeNextDose
                )
            }
        }

        // 3. Imminent dose (within 60 min)
        if let imminentTime = a.imminentDoseTime, let minutesAway = a.imminentDoseMinutesAway {
            return CabinetSummary(
                title: CabinetSummaryCopy.imminentDoseTitle(minutes: minutesAway),
                subtitle: CabinetSummaryCopy.imminentDoseSubtitle(time: formatTime(imminentTime)),
                state: .warning,
                priority: .imminentDose
            )
        }

        // 4. Refill within today
        if a.refillWithinTodayCount > 0 {
            let n = a.refillWithinTodayCount
            let subtitle = pharmacyDistanceText(from: pharmacy)
                .map { CabinetSummaryCopy.pharmacyNearby(distance: $0) } ?? ""
            return CabinetSummary(
                title: CabinetSummaryCopy.refillWithinTodayTitle(count: n),
                subtitle: subtitle,
                state: .warning,
                priority: .refillWithinToday
            )
        }

        // 5. Refill soon
        if a.refillSoonCount > 0 {
            let n = a.refillSoonCount
            let subtitle = pharmacyDistanceText(from: pharmacy)
                .map { CabinetSummaryCopy.pharmacyNearby(distance: $0) } ?? ""
            return CabinetSummary(
                title: CabinetSummaryCopy.refillSoonTitle(count: n),
                subtitle: subtitle,
                state: .info,
                priority: .refillSoon
            )
        }

        // 6. Next dose today
        if a.totalPendingDoseCount > 0 {
            let n = a.totalPendingDoseCount
            var subtitle = ""
            if let nextTime = a.nextUpcomingDoseTime {
                subtitle = CabinetSummaryCopy.nextDoseTodaySubtitle(time: formatTime(nextTime))
            }
            return CabinetSummary(
                title: CabinetSummaryCopy.nextDoseTodayTitle(count: n),
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

        // Imminent dose uses same inline format as next dose
        if a.imminentDoseTime != nil, let candidate = a.nextDoseCandidate {
            return CabinetInlineAction(
                text: CabinetSummaryCopy.inlineNextDose(
                    time: formatTime(candidate.time),
                    medicine: candidate.medicineName
                ),
                priority: .imminentDose
            )
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

    private func pharmacyDistanceText(from pharmacy: PharmacyInfo?) -> String? {
        guard let text = pharmacy?.distanceText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else { return nil }
        return text.replacingOccurrences(of: " · ", with: " o ")
    }
}
