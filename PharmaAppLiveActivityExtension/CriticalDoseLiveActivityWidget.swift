import WidgetKit
import SwiftUI
import AppIntents

struct CriticalDoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CriticalDoseLiveActivityAttributes.self) { context in
            if let confirmedName = context.state.confirmedTakenName {
                // ── Confirmation state ──
                confirmationBanner(medicineName: confirmedName)
                    .padding(10)
                    .activityBackgroundTint(Color(.systemBackground))
                    .activitySystemActionForegroundColor(.accentColor)
            } else {
                // ── Normal state ──
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "pills.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(context.attributes.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(countdownText(for: context.state.primaryScheduledAt))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("entro le \(Self.hourFormatter.string(from: context.state.primaryScheduledAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.primaryMedicineName)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(doseLine(for: context.state))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }

                    if #available(iOSApplicationExtension 17.0, *) {
                        HStack(spacing: 8) {
                            intentButton(
                                title: "Assunto",
                                intent: markTakenIntent(for: context.state),
                                prominent: true,
                                compact: false
                            )
                            intentButton(
                                title: "Ricordamelo dopo",
                                intent: remindLaterIntent(for: context.state),
                                prominent: false,
                                compact: false
                            )
                        }
                    }
                }
                .padding(10)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.accentColor)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.confirmedTakenName != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Fatto")
                                .font(.subheadline.weight(.semibold))
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "pills.fill")
                                .foregroundStyle(.secondary)
                            Text("È quasi ora")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.confirmedTakenName == nil {
                        Text(countdownText(for: context.state.primaryScheduledAt))
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let confirmedName = context.state.confirmedTakenName {
                        Text("\(confirmedName) segnato come assunto")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.primaryMedicineName)
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(doseLine(for: context.state))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.confirmedTakenName == nil {
                        if #available(iOSApplicationExtension 17.0, *) {
                            HStack(spacing: 8) {
                                intentButton(
                                    title: "Assunto",
                                    intent: markTakenIntent(for: context.state),
                                    prominent: true,
                                    compact: true
                                )
                                intentButton(
                                    title: "Ricordamelo dopo",
                                    intent: remindLaterIntent(for: context.state),
                                    prominent: false,
                                    compact: true
                                )
                            }
                        }
                    }
                }
            } compactLeading: {
                if context.state.confirmedTakenName != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "pills")
                }
            } compactTrailing: {
                if context.state.confirmedTakenName != nil {
                    Text("Assunto")
                        .font(.caption2.weight(.semibold))
                } else {
                    Text(context.state.primaryScheduledAt, style: .timer)
                        .monospacedDigit()
                        .frame(minWidth: 36)
                }
            } minimal: {
                if context.state.confirmedTakenName != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "pills")
                }
            }
            .widgetURL(URL(string: "pharmaapp://today"))
            .keylineTint(.accentColor)
        }
    }

    // MARK: - Confirmation Banner

    @ViewBuilder
    private func confirmationBanner(medicineName: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("\(medicineName) assunto")
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("Registrato correttamente")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func countdownText(for date: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSinceNow / 60)))
        switch minutes {
        case 0:
            return "Ora"
        case 1:
            return "Tra 1 min"
        default:
            return "Tra \(minutes) min"
        }
    }

    private func doseLine(for state: CriticalDoseLiveActivityAttributes.ContentState) -> String {
        var value = state.primaryDoseText
        if state.additionalCount > 0 {
            value += " · +\(state.additionalCount)"
        }
        return value
    }

    // MARK: - Intent Buttons

    @available(iOSApplicationExtension 17.0, *)
    @ViewBuilder
    private func intentButton(
        title: String,
        intent: some AppIntent,
        prominent: Bool,
        compact: Bool
    ) -> some View {
        Button(intent: intent) {
            Text(title)
                .font((compact ? Font.footnote : Font.callout).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 7 : 9)
                .padding(.horizontal, compact ? 8 : 10)
        }
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: compact ? 10 : 11, style: .continuous)
                .fill(prominent ? Color.accentColor : Color(.secondarySystemBackground))
        )
        .buttonStyle(.plain)
    }

    // MARK: - Intent Factories

    private func markTakenIntent(
        for state: CriticalDoseLiveActivityAttributes.ContentState
    ) -> LiveActivityMarkTakenIntent {
        LiveActivityMarkTakenIntent(
            therapyId: state.primaryTherapyId,
            medicineId: state.primaryMedicineId,
            medicineName: state.primaryMedicineName,
            doseText: state.primaryDoseText,
            scheduledAt: state.primaryScheduledAt
        )
    }

    private func remindLaterIntent(
        for state: CriticalDoseLiveActivityAttributes.ContentState
    ) -> LiveActivityRemindLaterIntent {
        LiveActivityRemindLaterIntent(
            therapyId: state.primaryTherapyId,
            medicineId: state.primaryMedicineId,
            medicineName: state.primaryMedicineName,
            doseText: state.primaryDoseText,
            scheduledAt: state.primaryScheduledAt
        )
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
