import SwiftUI

/// A single piece of the insights paragraph: plain text or an actionable task.
enum InsightSegment: Identifiable, Hashable {
    case text(String)
    case action(id: UUID, title: String, isDone: Bool)

    var id: UUID {
        switch self {
        case .text:
            // Generate a stable UUID based on the string hash to avoid unnecessary layout churn.
            return UUID()
        case .action(let id, _, _):
            return id
        }
    }
}

/// Renders a paragraph where actions are inline buttons with a circle + bold title.
struct TodayInsightsView: View {
    @State private var segments: [InsightSegment]

    init(segments: [InsightSegment]) {
        _segments = State(initialValue: segments)
    }

    var body: some View {
        ScrollView {
            FlowLayout(alignment: .leading, spacing: 6, rowSpacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { _, segment in
                    switch segment {
                    case .text(let string):
                        Text(string)
                            .font(.body)
                            .foregroundStyle(.primary)
                    case .action(let id, let title, let isDone):
                        Button {
                            toggleAction(id: id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                                Text(title)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }
            }
            .padding()
        }
    }

    private func toggleAction(id: UUID) {
        segments = segments.map { segment in
            guard case .action(let actionID, let title, let isDone) = segment else { return segment }
            return actionID == id ? .action(id: actionID, title: title, isDone: !isDone) : segment
        }
    }
}

// MARK: - Simple flow layout to wrap inline items across lines
struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
        return CGSize(width: width, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack {
        TodayInsightsView(segments: [
            .text("Oggi "),
            .action(id: UUID(), title: "compra il medicinale", isDone: false),
            .text(". La farmacia più vicina è CVS Pharmacy (133 m). Oggi "),
            .action(id: UUID(), title: "ricordati di assumere MOMENT alle 17:51", isDone: false),
            .text(" e "),
            .action(id: UUID(), title: "ATORVASTATINA MYLAN alle 23:50.", isDone: false)
        ])
    }
}
