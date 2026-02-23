import WidgetKit
import SwiftUI

struct CabinetSummaryEntry: TimelineEntry {
    let date: Date
    let lines: [String]
}

struct CabinetSummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> CabinetSummaryEntry {
        CabinetSummaryEntry(date: .now, lines: ["Tutto sotto controllo"])
    }

    func getSnapshot(in context: Context, completion: @escaping (CabinetSummaryEntry) -> Void) {
        let lines = readSharedLines()
        completion(CabinetSummaryEntry(date: .now, lines: lines.isEmpty ? ["Tutto sotto controllo"] : lines))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CabinetSummaryEntry>) -> Void) {
        let lines = readSharedLines()
        let entry = CabinetSummaryEntry(
            date: .now,
            lines: lines.isEmpty ? ["Tutto sotto controllo"] : lines
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readSharedLines() -> [String] {
        guard let defaults = UserDefaults(suiteName: "group.pharmapp-1987") else { return [] }
        return defaults.stringArray(forKey: "cabinetSummaryLines") ?? []
    }
}

struct CabinetSummaryWidgetView: View {
    let entry: CabinetSummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(entry.lines.prefix(3), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .description("Stato scorte e terapie")
        .supportedFamilies([.accessoryRectangular])
    }
}
