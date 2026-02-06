import SwiftUI

/// Riga generica per i todo di "Oggi" (versione senza sotto-task).
struct TodayTodoRowView: View {
    @ScaledMetric(relativeTo: .body) private var timingColumnWidth: CGFloat = 100

    let iconName: String
    let actionText: String?
    let leadingTime: String?
    let title: String
    let subtitle: String?
    let auxiliaryLine: Text?
    let auxiliaryUsesDefaultStyle: Bool
    let isCompleted: Bool
    let showToggle: Bool
    let hideToggle: Bool
    let trailingBadge: (String, Color)?
    let onToggle: () -> Void
    let subtitleFont: Font?
    let subtitleColor: Color?
    let auxiliaryFont: Font?
    let auxiliaryColor: Color?
    init(
        iconName: String,
        actionText: String? = nil,
        leadingTime: String? = nil,
        title: String,
        subtitle: String? = nil,
        auxiliaryLine: Text? = nil,
        auxiliaryUsesDefaultStyle: Bool = true,
        isCompleted: Bool,
        showToggle: Bool = true,
        hideToggle: Bool = false,
        trailingBadge: (String, Color)? = nil,
        onToggle: @escaping () -> Void,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil,
        auxiliaryFont: Font? = nil,
        auxiliaryColor: Color? = nil
    ) {
        self.iconName = iconName
        self.actionText = actionText
        self.leadingTime = leadingTime
        self.title = title
        self.subtitle = subtitle
        self.auxiliaryLine = auxiliaryLine
        self.auxiliaryUsesDefaultStyle = auxiliaryUsesDefaultStyle
        self.isCompleted = isCompleted
        self.showToggle = showToggle
        self.hideToggle = hideToggle
        self.trailingBadge = trailingBadge
        self.onToggle = onToggle
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
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
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let badge = trailingBadge {
                        badgeView(text: badge.0, color: badge.1)
                    }
                    if let auxiliaryLine {
                        let baseLine = auxiliaryLine
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .truncationMode(.tail)
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
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: size, weight: .regular))
                        .foregroundStyle(circleStrokeColor)
                        .frame(width: size, height: size)
                        .contentShape(Circle())
                        .accessibilityLabel(Text(iconName))
                }
                .buttonStyle(.plain)
                .disabled(!showToggle)
            }
        }
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
