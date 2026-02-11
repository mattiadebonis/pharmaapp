import WidgetKit
import SwiftUI

struct RefillLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RefillActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                Text(context.state.primaryText)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("\(context.state.etaMinutes) min")
                        .font(.subheadline.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(context.state.closingTimeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(purchaseSummaryText(for: context.state))
                    .font(.subheadline)
                    .lineLimit(1)

                if context.state.showHealthCardAction {
                    Link(destination: RefillLiveActivityURLBuilder.actionURL(.openHealthCard)) {
                        Text("Tessera sanitaria pronta")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Link(destination: RefillLiveActivityURLBuilder.mapsURL(
                        latitude: context.attributes.latitude,
                        longitude: context.attributes.longitude,
                        name: context.attributes.pharmacyName
                    )) {
                        Text("Naviga")
                    }
                    .buttonStyle(.borderedProminent)

                    Link(destination: RefillLiveActivityURLBuilder.actionURL(.openPurchaseList)) {
                        Text("Segna comprato")
                    }
                    .buttonStyle(.bordered)

                    Link(destination: RefillLiveActivityURLBuilder.actionURL(.dismissRefill)) {
                        Text("Non ora")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Rifornimenti")
                        .font(.headline)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.etaMinutes) min")
                        .font(.subheadline.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.closingTimeText)
                        .lineLimit(1)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Link(destination: RefillLiveActivityURLBuilder.mapsURL(
                            latitude: context.attributes.latitude,
                            longitude: context.attributes.longitude,
                            name: context.attributes.pharmacyName
                        )) {
                            Text("Naviga")
                        }
                        .buttonStyle(.borderedProminent)

                        Link(destination: RefillLiveActivityURLBuilder.actionURL(.openPurchaseList)) {
                            Text(shortPurchaseSummaryText(for: context.state))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } compactLeading: {
                Image(systemName: "cross.case.fill")
            } compactTrailing: {
                Text("\(context.state.etaMinutes)m")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "cross.case")
            }
            .widgetURL(RefillLiveActivityURLBuilder.mapsURL(
                latitude: context.attributes.latitude,
                longitude: context.attributes.longitude,
                name: context.attributes.pharmacyName
            ))
            .keylineTint(.accentColor)
        }
    }

    private func purchaseSummaryText(for state: RefillActivityAttributes.ContentState) -> String {
        let head = state.purchaseNames.joined(separator: ", ")
        if state.remainingPurchaseCount > 0 {
            return "Da comprare: \(head) +\(state.remainingPurchaseCount)"
        }
        return "Da comprare: \(head)"
    }

    private func shortPurchaseSummaryText(for state: RefillActivityAttributes.ContentState) -> String {
        let visible = Array(state.purchaseNames.prefix(2))
        let head = visible.joined(separator: ", ")
        let additional = max(0, state.purchaseNames.count - visible.count) + state.remainingPurchaseCount

        if additional > 0 {
            return "\(head) +\(additional)"
        }
        return head
    }
}
