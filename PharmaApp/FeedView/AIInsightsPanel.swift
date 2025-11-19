import SwiftUI

struct AIInsightsContext: Equatable {
    var purchaseHighlights: [String]
    var therapyHighlights: [String]
    var upcomingHighlights: [String]
    var prescriptionHighlights: [String]
    var pharmacySuggestion: String?

    var hasSignals: Bool {
        !(purchaseHighlights.isEmpty && therapyHighlights.isEmpty && upcomingHighlights.isEmpty && prescriptionHighlights.isEmpty)
    }

    var refreshKey: String {
        (purchaseHighlights + therapyHighlights + upcomingHighlights + prescriptionHighlights).joined(separator: "|")
    }

    var prompt: String {
        """
        Dati sullo stato dei farmaci e delle terapie di famiglia:

        - Farmaci da acquistare:
        \(formattedList(from: purchaseHighlights))

        - Terapie in programma oggi:
        \(formattedList(from: therapyHighlights))

        - Attività successive:
        \(formattedList(from: upcomingHighlights))

        - Stato ricette:
        \(formattedList(from: prescriptionHighlights))

        - Farmacia consigliata:
        \(pharmacySuggestion ?? "Nessuna farmacia suggerita")

        Scrivi in italiano un breve paragrafo discorsivo (massimo 4 frasi) che suggerisca le prossime azioni concrete per gestire farmaci e terapie. Usa un tono empatico ma pratico. Evidenzia urgenze come acquisti da fare subito o dosi imminenti.
        """
    }

    var fallbackSummary: String {
        var blocks: [String] = []
        if !purchaseHighlights.isEmpty {
            blocks.append("Da acquistare: \(purchaseHighlights.joined(separator: ", "))")
        }
        if !therapyHighlights.isEmpty {
            blocks.append("Terapie di oggi: \(therapyHighlights.joined(separator: ", "))")
        }
        if !upcomingHighlights.isEmpty {
            blocks.append("Prossimi promemoria: \(upcomingHighlights.joined(separator: ", "))")
        }
        if !prescriptionHighlights.isEmpty {
            blocks.append("Ricette: \(prescriptionHighlights.joined(separator: ", "))")
        }
        if let pharmacySuggestion {
            blocks.append("Farmacia: \(pharmacySuggestion)")
        }
        return blocks.joined(separator: "\n")
    }

    private func formattedList(from values: [String]) -> String {
        guard !values.isEmpty else { return "- Nessun elemento attuale." }
        return values.map { "- \($0)" }.joined(separator: "\n")
    }
}

struct AIInsightsPanel: View {
    let context: AIInsightsContext
    @StateObject private var viewModel = AIInsightsGenerator()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            iconView
            contentView
                .padding(10)
                .padding(.trailing, 20)
        }
        .alignmentGuide(.top) { d in d[.top] }
        .task(id: context.refreshKey) {
            await viewModel.generate(for: context)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(highlightedMessage)
                .foregroundStyle(.primary)
                .lineSpacing(10)
                .padding(.vertical, 6)
            if viewModel.state == .loading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                    .scaleEffect(0.8, anchor: .leading)
            }
        }
        .padding(.vertical, 12)
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.25),
                            Color.accentColor.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
            Image(systemName: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var mainMessage: String {
        switch viewModel.state {
        case .idle:
            return "Sto preparando dei suggerimenti personalizzati."
        case .loading:
            return "Analizzo terapie, ricette e scorte per proporti i prossimi passi."
        case .ready(let text):
            return text
        case .fallback(let text):
            return text
        }
    }

    private var highlightedMessage: AttributedString {
        var attributed = AttributedString(mainMessage.replacingOccurrences(of: ". ", with: ".\n").replacingOccurrences(of: "? ", with: "?\n"))
        attributed.font = .system(size: 23, weight: .regular, design: .rounded)

        let keywords = [
            "passa in farmacia",
            "ricordati",
            "assumi",
            "dose",
            "urgenti",
            "ricette",
            "organizzati",
            "prepara",
            "occupati"
        ]
        for keyword in keywords {
            highlightOccurrences(of: keyword, in: &attributed)
        }
        return attributed
    }

    private func highlightOccurrences(of keyword: String, in attributed: inout AttributedString) {
        let needle = keyword.lowercased()
        guard !needle.isEmpty else { return }

        let plain = String(attributed.characters).lowercased()
        var searchStart = plain.startIndex
        while let range = plain.range(of: needle, range: searchStart..<plain.endIndex) {
            let lowerOffset = plain.distance(from: plain.startIndex, to: range.lowerBound)
            let upperOffset = plain.distance(from: plain.startIndex, to: range.upperBound)
            let lower = attributed.index(attributed.startIndex, offsetByCharacters: lowerOffset)
            let upper = attributed.index(attributed.startIndex, offsetByCharacters: upperOffset)
            guard lower < attributed.endIndex, upper <= attributed.endIndex else { break }
            attributed[lower..<upper].font = .system(size: 23, weight: .semibold, design: .rounded)
            searchStart = range.upperBound
        }
    }

}

@MainActor
final class AIInsightsGenerator: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready(String)
        case fallback(String)
    }

    @Published private(set) var state: State = .idle

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    func generate(for context: AIInsightsContext) async {
        guard context.hasSignals else {
            state = .fallback("Al momento non ci sono attività urgenti: continua a monitorare con calma.")
            return
        }

        state = .loading
        await Task.yield()
        let message = Self.composeMessage(for: context)
        state = .ready(message)
    }

    private static func composeMessage(for context: AIInsightsContext) -> String {
        var sentences: [String] = []
        let purchaseItems = context.purchaseHighlights.compactMap { parseHighlight($0)?.name }
        if !purchaseItems.isEmpty {
            let listText = formattedList(from: purchaseItems)
            sentences.append("Compra \(listText).")
            if let pharmacy = context.pharmacySuggestion, !pharmacy.isEmpty {
                sentences.append("La farmacia più vicina è \(pharmacy).")
            }
        } else if let pharmacy = context.pharmacySuggestion, !pharmacy.isEmpty {
            sentences.append("La farmacia più vicina è \(pharmacy).")
        }
        let todayTherapies = context.therapyHighlights.compactMap { parseHighlight($0) }.compactMap { entry -> (name: String, time: String)? in
            guard let detail = entry.detail, let time = normalizedTodayTime(from: detail) else { return nil }
            return (entry.name, time)
        }
        if !todayTherapies.isEmpty {
            let descriptions = todayTherapies.map { "\($0.name) alle \($0.time)" }
            let joined = descriptions.joined(separator: ", ")
            sentences.append("Oggi ricordati di assumere \(joined).")
        }
        if let nextTask = context.upcomingHighlights.first, let parsed = parseHighlight(nextTask) {
            if let detail = parsed.detail, !detail.isEmpty {
                sentences.append("Nei prossimi giorni organizzati per \(parsed.name.lowercased()) \(detail).")
            } else {
                sentences.append("Prepara con anticipo \(parsed.name.lowercased()) così resti tranquillo.")
            }
        }
        if let prescriptionTask = context.prescriptionHighlights.first, let parsed = parseHighlight(prescriptionTask) {
            if let detail = parsed.detail, !detail.isEmpty {
                sentences.append("Per le ricette occupati di \(parsed.name.lowercased()) \(detail).")
            } else {
                sentences.append("Segui il flusso ricette per \(parsed.name.lowercased()) appena possibile.")
            }
        }
        if sentences.isEmpty {
            return context.fallbackSummary
        }
        return sentences.joined(separator: " ")
    }

    private static func formattedList(from items: [String]) -> String {
        guard let first = items.first else { return "" }
        if items.count == 1 { return first }
        let head = items.dropLast().joined(separator: ", ")
        return "\(head) e \(items.last!)"
    }

    private static func parseHighlight(_ highlight: String) -> (name: String, detail: String?)? {
        let components = highlight.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let name = components.first, !name.isEmpty else { return nil }
        let detail = components.count > 1 ? components[1] : nil
        return (name: name, detail: detail)
    }

    private static func normalizedTodayTime(from detail: String) -> String? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[0-9]{1,2}:[0-9]{2}$"
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return trimmed
        }
        return nil
    }
}
