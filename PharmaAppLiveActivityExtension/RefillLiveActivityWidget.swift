import WidgetKit
import SwiftUI

struct RefillLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RefillActivityAttributes.self) { context in
            let canNavigate = context.attributes.latitude != 0 || context.attributes.longitude != 0

            VStack(alignment: .leading, spacing: 10) {
                Text(context.state.primaryText)
                    .font(.headline)

                Text(context.state.pharmacyName ?? "Farmacia più vicina")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(etaText(for: context.state))
                        .font(.subheadline.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(context.state.pharmacyHoursText ?? "orari non disponibili")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(purchaseSummaryText(for: context.state))
                    .font(.subheadline)
                    .lineLimit(2)

                Text("Medico \(context.state.doctorName): \(context.state.doctorHoursText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if context.state.showHealthCardAction {
                    Link(destination: RefillLiveActivityURLBuilder.actionURL(.openHealthCard)) {
                        Text("Tessera sanitaria pronta")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    if canNavigate {
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
                    } else {
                        Link(destination: RefillLiveActivityURLBuilder.actionURL(.openPurchaseList)) {
                            Text("Segna comprato")
                        }
                        .buttonStyle(.borderedProminent)
                    }

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
                    Text("Scorte")
                        .font(.headline)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(etaText(for: context.state))
                        .font(.subheadline.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.pharmacyName ?? "Farmacia più vicina")
                            .lineLimit(1)
                            .font(.footnote.weight(.semibold))
                        Text(context.state.pharmacyHoursText ?? "orari non disponibili")
                            .lineLimit(1)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(context.state.doctorName): \(context.state.doctorHoursText)")
                            .lineLimit(1)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        if context.attributes.latitude != 0 || context.attributes.longitude != 0 {
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
                        } else {
                            Link(destination: RefillLiveActivityURLBuilder.actionURL(.openPurchaseList)) {
                                Text(shortPurchaseSummaryText(for: context.state))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "cross.case.fill")
            } compactTrailing: {
                Text(compactEtaText(for: context.state))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "cross.case")
            }
            .widgetURL(
                (context.attributes.latitude == 0 && context.attributes.longitude == 0)
                    ? RefillLiveActivityURLBuilder.actionURL(.openPurchaseList)
                    : RefillLiveActivityURLBuilder.mapsURL(
                        latitude: context.attributes.latitude,
                        longitude: context.attributes.longitude,
                        name: context.attributes.pharmacyName
                    )
            )
            .keylineTint(.accentColor)
        }
    }

    private func purchaseSummaryText(for state: RefillActivityAttributes.ContentState) -> String {
        let head = state.purchaseNames.joined(separator: ", ")
        if state.remainingPurchaseCount > 0 {
            return "Sotto soglia: \(head) +\(state.remainingPurchaseCount)"
        }
        return "Sotto soglia: \(head)"
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

    private func etaText(for state: RefillActivityAttributes.ContentState) -> String {
        let eta = state.etaMinutes ?? 0
        if eta > 0 {
            return "\(eta) min"
        }
        return "stima non disponibile"
    }

    private func compactEtaText(for state: RefillActivityAttributes.ContentState) -> String {
        let eta = state.etaMinutes ?? 0
        if eta > 0 {
            return "\(eta)m"
        }
        return "--"
    }
}
