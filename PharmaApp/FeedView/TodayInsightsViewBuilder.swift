import Foundation

/// Helper to convert the existing AIInsightsContext into inline segments for TodayInsightsView.
enum TodayInsightsViewBuilder {
    static func buildSegments(from context: AIInsightsContext) -> [InsightSegment] {
        var segments: [InsightSegment] = []

        func appendText(_ text: String) {
            guard !text.isEmpty else { return }
            segments.append(.text(text))
        }

        func appendActions(_ titles: [String], prefix: String = "", separator: String = " e ") {
            guard !titles.isEmpty else { return }
            for (idx, title) in titles.enumerated() {
                if idx == 0, !prefix.isEmpty { appendText(prefix) }
                if idx > 0 { appendText(separator) }
                segments.append(.action(id: UUID(), title: title, isDone: false))
            }
        }

        appendText("Oggi ")
        appendActions(context.purchaseHighlights.map { trimTaskText($0) }, prefix: "")

        if let pharmacy = context.pharmacySuggestion {
            appendText(". La farmacia più vicina è \(pharmacy). Oggi ")
        } else {
            appendText(". Oggi ")
        }

        appendActions(context.therapyHighlights.map { trimTaskText($0) })

        if !context.prescriptionHighlights.isEmpty {
            appendText(". ")
            appendActions(context.prescriptionHighlights.map { trimTaskText($0) }, prefix: "")
        }

        if segments.isEmpty {
            appendText("Oggi non hai attività urgenti.")
        }

        return segments
    }

    private static func trimTaskText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
