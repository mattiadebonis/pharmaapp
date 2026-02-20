import SwiftUI

/// Riga generica per i todo di "Oggi" (versione senza sotto-task).
struct TodayTodoRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconName: String
    let actionText: String?
    let leadingTime: String?
    let title: String
    let titleStatusIconName: String?
    let titleStatusIconColor: Color?
    let titleStatusIconAccessibilityLabel: String?
    let subtitle: String?
    let subtitleLine: Text?
    let auxiliaryLine: Text?
    let auxiliaryUsesDefaultStyle: Bool
    let isCompleted: Bool
    let isToggleOn: Bool
    let showToggle: Bool
    let hideToggle: Bool
    let trailingBadge: (String, Color)?
    let trailingBadgeAction: (() -> Void)?
    let onToggle: () -> Void
    let subtitleFont: Font?
    let subtitleColor: Color?
    let subtitleAlignsWithTitle: Bool
    let auxiliaryFont: Font?
    let auxiliaryColor: Color?
    init(
        iconName: String,
        actionText: String? = nil,
        leadingTime: String? = nil,
        title: String,
        titleStatusIconName: String? = nil,
        titleStatusIconColor: Color? = nil,
        titleStatusIconAccessibilityLabel: String? = nil,
        subtitle: String? = nil,
        subtitleLine: Text? = nil,
        auxiliaryLine: Text? = nil,
        auxiliaryUsesDefaultStyle: Bool = true,
        isCompleted: Bool,
        isToggleOn: Bool? = nil,
        showToggle: Bool = true,
        hideToggle: Bool = false,
        trailingBadge: (String, Color)? = nil,
        trailingBadgeAction: (() -> Void)? = nil,
        onToggle: @escaping () -> Void,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil,
        subtitleAlignsWithTitle: Bool = false,
        auxiliaryFont: Font? = nil,
        auxiliaryColor: Color? = nil
    ) {
        self.iconName = iconName
        self.actionText = actionText
        self.leadingTime = leadingTime
        self.title = title
        self.titleStatusIconName = titleStatusIconName
        self.titleStatusIconColor = titleStatusIconColor
        self.titleStatusIconAccessibilityLabel = titleStatusIconAccessibilityLabel
        self.subtitle = subtitle
        self.subtitleLine = subtitleLine
        self.auxiliaryLine = auxiliaryLine
        self.auxiliaryUsesDefaultStyle = auxiliaryUsesDefaultStyle
        self.isCompleted = isCompleted
        self.isToggleOn = isToggleOn ?? isCompleted
        self.showToggle = showToggle
        self.hideToggle = hideToggle
        self.trailingBadge = trailingBadge
        self.trailingBadgeAction = trailingBadgeAction
        self.onToggle = onToggle
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.subtitleAlignsWithTitle = subtitleAlignsWithTitle
        self.auxiliaryFont = auxiliaryFont
        self.auxiliaryColor = auxiliaryColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if !hideToggle {
                Button(action: onToggle) {
                    let size: CGFloat = 18
                    ZStack {
                        Circle()
                            .stroke(checkboxBorderColor, lineWidth: 1.2)
                            .background(
                                Circle()
                                    .fill(isToggleOn ? checkboxFillColor.opacity(0.24) : .clear)
                            )
                        if isToggleOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(checkboxCheckmarkColor)
                        }
                    }
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                    .accessibilityLabel(Text(iconName))
                }
                .buttonStyle(.plain)
                .disabled(!showToggle)
                .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(primaryLineTitle)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if let titleStatusIconName, !titleStatusIconName.isEmpty {
                        Image(systemName: titleStatusIconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(titleStatusIconColor ?? secondaryTextColor)
                            .accessibilityLabel(Text(titleStatusIconAccessibilityLabel ?? titleStatusIconName))
                    }
                }

                if let leadingTime, !leadingTime.isEmpty {
                    Text(formatTimingLine(leadingTime))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(secondaryTextColor)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                if let actionText, !actionText.isEmpty {
                    Text(actionText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(labelColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                if let subtitleLine {
                    subtitleLine
                        .font(subtitleFont ?? .system(size: 15))
                        .foregroundStyle(subtitleColor ?? secondaryTextColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .truncationMode(.tail)
                } else if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(subtitleFont ?? .system(size: 15))
                        .foregroundStyle(subtitleColor ?? secondaryTextColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }

                if let auxiliaryLine {
                    let baseLine = auxiliaryLine
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .truncationMode(.tail)
                    if auxiliaryUsesDefaultStyle {
                        baseLine
                            .font(auxiliaryFont ?? .system(size: 15))
                            .foregroundStyle(auxiliaryColor ?? secondaryTextColor)
                    } else {
                        baseLine
                    }
                }

                if let badge = trailingBadge {
                    if let trailingBadgeAction {
                        Button(action: trailingBadgeAction) {
                            badgeView(text: badge.0, color: badge.1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        badgeView(text: badge.0, color: badge.1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard trailingBadgeAction == nil else { return }
                if showToggle && !hideToggle { onToggle() }
            }
        }
    }

    private var titleColor: Color {
        isCompleted ? completedTextColor : primaryTextColor
    }

    private var labelColor: Color {
        isCompleted ? completedTextColor : primaryTextColor
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.8) : Color.primary.opacity(0.45)
    }

    private var circleStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : Color.primary.opacity(0.25)
    }

    private var checkboxBorderColor: Color {
        colorScheme == .dark ? .white.opacity(0.9) : circleStrokeColor
    }

    private var checkboxFillColor: Color {
        colorScheme == .dark ? .white.opacity(0.9) : Color.primary.opacity(0.55)
    }

    private var checkboxCheckmarkColor: Color {
        colorScheme == .dark ? .black.opacity(0.9) : .white
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var completedTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .secondary
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(colorScheme == .dark ? 0.25 : 0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(colorScheme == .dark ? 0.55 : 0.35), lineWidth: 0.8)
            )
    }

    private var primaryLineTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        guard let actionText else { return "" }
        return actionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatTimingLine(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("alle ") else { return trimmed }
        let time = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        if time.isEmpty { return trimmed }
        return time
    }
}
