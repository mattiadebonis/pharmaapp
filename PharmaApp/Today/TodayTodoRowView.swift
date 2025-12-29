import SwiftUI

/// Riga generica per i todo di "Oggi" (versione senza sotto-task).
struct TodayTodoRowView: View {
    let iconName: String
    let actionText: String?
    let title: String
    let subtitle: String?
    let auxiliaryLine: Text?
    let isCompleted: Bool
    let showToggle: Bool
    let trailingBadge: (String, Color)?
    let onToggle: () -> Void
    
    init(
        iconName: String,
        actionText: String? = nil,
        title: String,
        subtitle: String? = nil,
        auxiliaryLine: Text? = nil,
        isCompleted: Bool,
        showToggle: Bool = true,
        trailingBadge: (String, Color)? = nil,
        onToggle: @escaping () -> Void
    ) {
        self.iconName = iconName
        self.actionText = actionText
        self.title = title
        self.subtitle = subtitle
        self.auxiliaryLine = auxiliaryLine
        self.isCompleted = isCompleted
        self.showToggle = showToggle
        self.trailingBadge = trailingBadge
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(labelColor)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let actionText, !actionText.isEmpty {
                        Text(actionText)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(labelColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .layoutPriority(2)
                    }

                    Text(title)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let auxiliaryLine {
                        auxiliaryLine
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let badge = trailingBadge {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(badge.1)
                    Text(badge.0)
                        .font(.callout)
                        .foregroundStyle(badge.1)
                }
            }

            if showToggle {
                Button(action: onToggle) {
                    Image(systemName: isCompleted ? "circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    private var titleColor: Color {
        isCompleted ? .secondary : .primary
    }

    private var labelColor: Color {
        isCompleted ? .secondary : .primary
    }
}
