import WidgetKit
import SwiftUI

struct CriticalDoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CriticalDoseLiveActivityAttributes.self) { context in
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
                        actionLink(
                            title: "Assunto",
                            destination: actionURL(for: context.state, action: .markTaken),
                            prominent: true,
                            compact: false
                        )
                        actionLink(
                            title: "Ricordamelo dopo",
                            destination: actionURL(for: context.state, action: .remindLater),
                            prominent: false,
                            compact: false
                        )
                    }
                }
            }
            .padding(10)
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "pills.fill")
                            .foregroundStyle(.secondary)
                        Text("È quasi ora")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(countdownText(for: context.state.primaryScheduledAt))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.center) {
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
                DynamicIslandExpandedRegion(.bottom) {
                    if #available(iOSApplicationExtension 17.0, *) {
                        HStack(spacing: 8) {
                            actionLink(
                                title: "Assunto",
                                destination: actionURL(for: context.state, action: .markTaken),
                                prominent: true,
                                compact: true
                            )
                            actionLink(
                                title: "Ricordamelo dopo",
                                destination: actionURL(for: context.state, action: .remindLater),
                                prominent: false,
                                compact: true
                            )
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "pills")
            } compactTrailing: {
                Text(context.state.primaryScheduledAt, style: .timer)
                    .monospacedDigit()
                    .frame(minWidth: 36)
            } minimal: {
                Image(systemName: "pills")
            }
            .widgetURL(URL(string: "pharmaapp://today"))
            .keylineTint(.accentColor)
        }
    }

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

    @ViewBuilder
    private func actionLink(
        title: String,
        destination: URL,
        prominent: Bool,
        compact: Bool
    ) -> some View {
        Link(destination: destination) {
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
    }

    private func actionURL(
        for state: CriticalDoseLiveActivityAttributes.ContentState,
        action: LiveActivityActionURLBuilder.Action
    ) -> URL {
        LiveActivityActionURLBuilder.makeURL(
            action: action,
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
