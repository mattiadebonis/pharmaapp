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
    let subtitleFont: Font?
    let subtitleColor: Color?
    let auxiliaryFont: Font?
    let auxiliaryColor: Color?
    init(
        iconName: String,
        actionText: String? = nil,
        title: String,
        subtitle: String? = nil,
        auxiliaryLine: Text? = nil,
        isCompleted: Bool,
        showToggle: Bool = true,
        trailingBadge: (String, Color)? = nil,
        onToggle: @escaping () -> Void,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil,
        auxiliaryFont: Font? = nil,
        auxiliaryColor: Color? = nil
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
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.auxiliaryFont = auxiliaryFont
        self.auxiliaryColor = auxiliaryColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? circleStrokeColor.opacity(0.2) : .clear)
                    Circle()
                        .stroke(circleStrokeColor, lineWidth: 1.3)
                }
                .frame(width: 18, height: 18)
                .accessibilityLabel(Text(iconName))
            }
            .buttonStyle(.plain)
            .disabled(!showToggle)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let actionText, !actionText.isEmpty {
                        Text(actionText)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(labelColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .layoutPriority(2)
                    }

                    Text(title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let subtitle {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(subtitle)
                                .font(subtitleFont ?? .system(size: 15))
                                .foregroundStyle(subtitleColor ?? secondaryTextColor)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            if let badge = trailingBadge {
                                badgeView(text: badge.0, color: badge.1)
                            }
                        }
                    } else if let badge = trailingBadge {
                        badgeView(text: badge.0, color: badge.1)
                    }
                    if let auxiliaryLine {
                        auxiliaryLine
                            .font(auxiliaryFont ?? .system(size: 15))
                            .foregroundStyle(auxiliaryColor ?? secondaryTextColor)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showToggle {
                // Toggle handled by leading circle
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if showToggle { onToggle() } }
    }

    private var titleColor: Color {
        isCompleted ? .secondary : .primary
    }

    private var labelColor: Color {
        isCompleted ? .secondary : .primary
    }

    private var secondaryTextColor: Color {
        Color.primary.opacity(0.45)
    }

    private var circleStrokeColor: Color {
        Color.primary.opacity(0.25)
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 2)
    }
}
