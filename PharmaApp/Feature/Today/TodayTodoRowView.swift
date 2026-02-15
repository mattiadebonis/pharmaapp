import SwiftUI

/// Riga generica per i todo di "Oggi" (versione senza sotto-task).
struct TodayTodoRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var timingColumnWidth: CGFloat = 100

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
        self.onToggle = onToggle
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.subtitleAlignsWithTitle = subtitleAlignsWithTitle
        self.auxiliaryFont = auxiliaryFont
        self.auxiliaryColor = auxiliaryColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let leadingTime, !leadingTime.isEmpty {
                        Text(leadingTime)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(secondaryTextColor)
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.85)
                            .frame(width: timingColumnWidth, alignment: .leading)
                            .layoutPriority(2)
                    }

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

                    if let titleStatusIconName, !titleStatusIconName.isEmpty {
                        Image(systemName: titleStatusIconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(titleStatusIconColor ?? secondaryTextColor)
                            .accessibilityLabel(Text(titleStatusIconAccessibilityLabel ?? titleStatusIconName))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let badge = trailingBadge {
                        badgeView(text: badge.0, color: badge.1)
                    }
                    if let subtitleLine {
                        subtitleLine
                            .font(subtitleFont ?? .system(size: 15))
                            .foregroundStyle(subtitleColor ?? secondaryTextColor)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .padding(.leading, subtitleLeadingInset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(subtitleFont ?? .system(size: 15))
                            .foregroundStyle(subtitleColor ?? secondaryTextColor)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .padding(.leading, subtitleLeadingInset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let auxiliaryLine {
                        let baseLine = auxiliaryLine
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .padding(.leading, subtitleLeadingInset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if auxiliaryUsesDefaultStyle {
                            baseLine
                                .font(auxiliaryFont ?? .system(size: 15))
                                .foregroundStyle(auxiliaryColor ?? secondaryTextColor)
                        } else {
                            baseLine
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if showToggle && !hideToggle { onToggle() } }

            if !hideToggle {
                Button(action: onToggle) {
                    let size: CGFloat = 18
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(checkboxBorderColor, lineWidth: 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isToggleOn ? checkboxFillColor : .clear)
                            )
                        if isToggleOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(checkboxCheckmarkColor)
                        }
                    }
                        .frame(width: size, height: size)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityLabel(Text(iconName))
                }
                .buttonStyle(.plain)
                .disabled(!showToggle)
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
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 2)
    }

    private var subtitleLeadingInset: CGFloat {
        guard subtitleAlignsWithTitle else { return 0 }
        guard let leadingTime, !leadingTime.isEmpty else { return 0 }
        return timingColumnWidth + 8
    }
}
