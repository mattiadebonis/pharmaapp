import SwiftUI

/// Riga generica per i todo di "Oggi" (versione senza sotto-task).
struct TodayTodoRowView: View {
    let iconName: String
    let actionText: String?
    let leadingTime: String?
    let reserveLeadingTimeSpace: Bool
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
        reserveLeadingTimeSpace: Bool = true,
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
        self.reserveLeadingTimeSpace = reserveLeadingTimeSpace
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
            if reserveLeadingTimeSpace {
                leadingTimeView
            } else if let leadingTime, !leadingTime.isEmpty {
                let isMultiline = leadingTime.contains("\n")
                Text(leadingTime)
                    .foregroundStyle(secondaryTextColor)
                    .monospacedDigit()
                    .multilineTextAlignment(isMultiline ? .center : .leading)
                    .frame(minWidth: 60, alignment: isMultiline ? .center : .leading)
                    .padding(.top, 2)
            }
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

            if !hideToggle {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
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
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if showToggle && !hideToggle { onToggle() } }
    }

    private var leadingTimeView: some View {
        let text = leadingTime ?? ""
        let isMultiline = text.contains("\n")
        return Text(text)
            .foregroundStyle(secondaryTextColor)
            .monospacedDigit()
            .multilineTextAlignment(isMultiline ? .center : .leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 60, alignment: isMultiline ? .center : .leading)
            .padding(.top, 2)
            .opacity(text.isEmpty ? 0 : 1)
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
