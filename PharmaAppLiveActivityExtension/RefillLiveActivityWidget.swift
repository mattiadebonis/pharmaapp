import WidgetKit
import SwiftUI

struct RefillLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RefillActivityAttributes.self) { context in
            let items = sortedItems(for: context.state)
            let hero = items.first
            let others = Array(items.dropFirst().prefix(3))
            let extraCount = max(0, items.count - 1 - others.count)
            let canNavigate = context.attributes.latitude != 0 || context.attributes.longitude != 0
            let minDaysValue = minDays(items: items)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // LOCK SCREEN BANNER
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            VStack(alignment: .leading, spacing: 0) {

                // ── FARMACIA ──
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.pharmacyName ?? "Farmacia più vicina")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(context.state.isPharmacyOpen ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            Text(pharmacyStatusText(context: context))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    // ETA badge → tap apre Apple Maps
                    if canNavigate {
                        Link(destination: RefillLiveActivityURLBuilder.mapsURL(
                            latitude: context.attributes.latitude,
                            longitude: context.attributes.longitude,
                            name: context.attributes.pharmacyName
                        )) {
                            HStack(spacing: 4) {
                                Image(systemName: context.state.isWalking ? "figure.walk" : "car.fill")
                                    .font(.caption2.weight(.bold))
                                if let eta = context.state.etaMinutes, eta > 0 {
                                    Text("\(eta) min")
                                        .font(.subheadline.weight(.heavy).monospacedDigit())
                                } else {
                                    Text("Mappa")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .modifier(GlassCapsuleModifier())
                        }
                    }
                }
                .padding(.bottom, 12)

                // Divider
                Rectangle()
                    .fill(.primary.opacity(0.1))
                    .frame(height: 1)
                    .padding(.bottom, 10)

                // ── FARMACI DA RIFORNIRE ──

                // Giorni rimasti (minimo globale)
                if let days = minDaysValue {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                        Text("Scorte per \(days) \(days == 1 ? "giorno" : "giorni")")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.bottom, 8)
                }

                // Lista farmaci (link → apre lista acquisti nell'app)
                Link(destination: RefillLiveActivityURLBuilder.actionURL(.openPurchaseList)) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let hero {
                            HStack(spacing: 0) {
                                Text(hero.name)
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if let units = hero.remainingUnits {
                                    Text("\(units) compresse")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        ForEach(Array(others.enumerated()), id: \.element.name) { _, item in
                            HStack(spacing: 0) {
                                Text(item.name)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary.opacity(0.8))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if let units = item.remainingUnits {
                                    Text("\(units) compresse")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if extraCount > 0 {
                            Text("+\(extraCount) altri farmaci")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Codice Fiscale
                if !context.state.codiceFiscaleEntries.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(context.state.codiceFiscaleEntries.enumerated()), id: \.element.codiceFiscale) { index, entry in
                            if index > 0 { Text("  ") }
                            Image(systemName: "doc.text").font(.caption2)
                            Text(" \(entry.personName): \(entry.codiceFiscale)")
                                .font(.caption2.monospaced())
                        }
                    }
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 6)
                }
            }
            .padding(14)
            .modifier(ActivityBackgroundModifier())

        } dynamicIsland: { context in
            let items = sortedItems(for: context.state)
            let hero = items.first
            let others = Array(items.dropFirst().prefix(2))
            let extraCount = max(0, items.count - 1 - others.count)
            let heroDays = hero?.autonomyDays ?? minDays(items: items)

            return DynamicIsland {
                // ── Expanded ──
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let heroDays {
                            Text("\(heroDays)g")
                                .font(.title2.weight(.heavy))
                                .monospacedDigit()
                        }
                        HStack(spacing: 3) {
                            Circle()
                                .fill(context.state.isPharmacyOpen ? Color.green : Color.red)
                                .frame(width: 5, height: 5)
                            Text(context.state.isPharmacyOpen ? "Aperta" : "Chiusa")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.pharmacyName ?? "Farmacia")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                        if let eta = context.state.etaMinutes, eta > 0,
                           context.attributes.latitude != 0 || context.attributes.longitude != 0 {
                            Link(destination: RefillLiveActivityURLBuilder.mapsURL(
                                latitude: context.attributes.latitude,
                                longitude: context.attributes.longitude,
                                name: context.attributes.pharmacyName
                            )) {
                                HStack(spacing: 2) {
                                    Image(systemName: context.state.isWalking ? "figure.walk" : "car.fill")
                                        .font(.caption2)
                                    Text("\(eta) min")
                                        .font(.caption2.weight(.bold))
                                        .monospacedDigit()
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let hero {
                            HStack(spacing: 0) {
                                Text(hero.name)
                                    .font(.caption.weight(.heavy))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if let units = hero.remainingUnits {
                                    Text("\(units) cpr")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !others.isEmpty {
                            HStack(spacing: 0) {
                                ForEach(Array(others.enumerated()), id: \.element.name) { index, item in
                                    if index > 0 {
                                        Text(" · ").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Text(item.name).font(.caption2.weight(.semibold))
                                }
                                if extraCount > 0 {
                                    Text(" +\(extraCount)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(context.state.isPharmacyOpen ? Color.green : Color.red)
                        .frame(width: 5, height: 5)
                    Text("\(heroDays ?? 0)g")
                        .font(.headline.weight(.heavy))
                        .monospacedDigit()
                }
            } compactTrailing: {
                if items.count > 1 {
                    Text("+\(items.count - 1)")
                        .font(.caption2.weight(.bold))
                } else if let hero {
                    Text(compactName(hero.name))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
            } minimal: {
                Text("\(heroDays ?? 0)g")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
            }
            .widgetURL(RefillLiveActivityURLBuilder.actionURL(.openPurchaseList))
        }
    }

    // MARK: - Helpers

    private func pharmacyStatusText(context: ActivityViewContext<RefillActivityAttributes>) -> String {
        let status = context.state.isPharmacyOpen ? "Aperta" : "Chiusa"
        if let hoursText = context.state.pharmacyHoursText,
           !hoursText.isEmpty,
           hoursText != "orari non disponibili" {
            return "\(status) · \(hoursText)"
        }
        return status
    }

    // MARK: - Data

    private func sortedItems(for state: RefillActivityAttributes.ContentState) -> [RefillActivityAttributes.PurchaseItem] {
        let items: [RefillActivityAttributes.PurchaseItem]
        if !state.purchaseItems.isEmpty {
            items = state.purchaseItems
        } else {
            items = state.purchaseNames.map {
                RefillActivityAttributes.PurchaseItem(name: $0, autonomyDays: nil, remainingUnits: nil)
            }
        }
        return items.sorted { lhs, rhs in
            let ld = lhs.autonomyDays ?? Int.max
            let rd = rhs.autonomyDays ?? Int.max
            if ld != rd { return ld < rd }
            let lu = lhs.remainingUnits ?? Int.max
            let ru = rhs.remainingUnits ?? Int.max
            return lu < ru
        }
    }

    private func minDays(items: [RefillActivityAttributes.PurchaseItem]) -> Int? {
        items.compactMap(\.autonomyDays).min()
    }

    private func compactName(_ name: String) -> String {
        if name.count <= 6 { return name }
        return String(name.prefix(5)) + "…"
    }
}

// MARK: - Glass Compatibility

private struct ActivityBackgroundModifier: ViewModifier {
    private static let green = Color(red: 0.18, green: 0.70, blue: 0.40)

    func body(content: Content) -> some View {
        content
            .activityBackgroundTint(Self.green)
            .activitySystemActionForegroundColor(.white)
    }
}

private struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(
                Capsule().fill(.ultraThinMaterial)
            )
        }
    }
}
