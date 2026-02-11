import WidgetKit
import SwiftUI

struct CriticalDoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CriticalDoseLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.title)
                    .font(.headline)

                Text(mainLine(for: context.state.primaryScheduledAt))
                    .font(.title3.weight(.semibold))

                Text(context.state.subtitleDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(context.attributes.microcopy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if #available(iOSApplicationExtension 17.0, *) {
                    HStack(spacing: 8) {
                        Link(destination: actionURL(for: context.state, action: .markTaken)) {
                            Text("Assunto")
                        }
                        .buttonStyle(.borderedProminent)

                        Link(destination: actionURL(for: context.state, action: .remindLater)) {
                            Text("Ricordamelo dopo")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("È quasi ora")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.primaryScheduledAt, style: .timer)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.subtitleDisplay)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if #available(iOSApplicationExtension 17.0, *) {
                        HStack(spacing: 8) {
                            Link(destination: actionURL(for: context.state, action: .markTaken)) {
                                Text("Assunto")
                            }
                            .buttonStyle(.borderedProminent)

                            Link(destination: actionURL(for: context.state, action: .remindLater)) {
                                Text("Ricordamelo dopo")
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Text(context.attributes.microcopy)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

    private func mainLine(for date: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSinceNow / 60)))
        let minuteText = minutes == 1 ? "1 minuto" : "\(minutes) minuti"
        let hourText = Self.hourFormatter.string(from: date)
        return "Tra \(minuteText) · entro le \(hourText)"
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
