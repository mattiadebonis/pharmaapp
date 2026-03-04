import WidgetKit
import SwiftUI

struct CabinetSummaryEntry: TimelineEntry {
    let date: Date
    let lines: [String]
    let inlineText: String
}

struct CabinetSummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> CabinetSummaryEntry {
        CabinetSummaryEntry(
            date: .now,
            lines: ["Tutto sotto controllo"],
            inlineText: "Tutto sotto controllo"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CabinetSummaryEntry) -> Void) {
        let lines = resolvedLines()
        completion(
            CabinetSummaryEntry(
                date: .now,
                lines: lines,
                inlineText: resolvedInlineText(lines: lines)
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CabinetSummaryEntry>) -> Void) {
        let lines = resolvedLines()
        let entry = CabinetSummaryEntry(
            date: .now,
            lines: lines,
            inlineText: resolvedInlineText(lines: lines)
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readSharedLines() -> [String] {
        guard let defaults = UserDefaults(suiteName: "group.pharmapp-1987") else { return [] }
        return defaults.stringArray(forKey: "cabinetSummaryLines") ?? []
    }

    private func readInlineText() -> String? {
        guard let defaults = UserDefaults(suiteName: "group.pharmapp-1987") else { return nil }
        return defaults.string(forKey: "cabinetSummaryInlineAction")
    }

    private func resolvedLines() -> [String] {
        let lines = readSharedLines()
        return lines.isEmpty ? ["Tutto sotto controllo"] : lines
    }

    private func resolvedInlineText(lines: [String]) -> String {
        let fallback = lines.first ?? "Tutto sotto controllo"
        let inline = readInlineText()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return inline.isEmpty ? fallback : inline
    }
}

struct CabinetSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CabinetSummaryEntry

    var body: some View {
        Group {
            if family == .accessoryInline {
                Text(entry.inlineText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(entry.lines.prefix(3).enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(index == 0 ? .caption.bold() : .caption2)
                            .minimumScaleFactor(0.7)
                            .lineLimit(index == 0 ? 2 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "pharmaapp://today"))
    }
}

struct CabinetSummaryWidget: Widget {
    let kind = "CabinetSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CabinetSummaryProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                CabinetSummaryWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                CabinetSummaryWidgetView(entry: entry)
                    .padding()
            }
        }
        .configurationDisplayName("Sommario")
        .description("Stato scorte e prossima azione")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
