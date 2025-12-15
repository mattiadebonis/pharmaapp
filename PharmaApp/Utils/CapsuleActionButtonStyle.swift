import SwiftUI

struct CapsuleActionButtonStyle: ButtonStyle {
    let fill: Color
    let textColor: Color
    let verticalPadding: CGFloat

    init(fill: Color, textColor: Color, verticalPadding: CGFloat = 18) {
        self.fill = fill
        self.textColor = textColor
        self.verticalPadding = verticalPadding
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(textColor)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
