import SwiftUI

struct CapsuleActionButtonStyle: ButtonStyle {
    let fill: Color
    let textColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(textColor)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
