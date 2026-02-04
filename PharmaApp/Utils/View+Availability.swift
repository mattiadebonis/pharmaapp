import SwiftUI

extension View {
    @ViewBuilder
    func listSectionSpacingIfAvailable(_ spacing: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(spacing)
        } else {
            self
        }
    }
}
