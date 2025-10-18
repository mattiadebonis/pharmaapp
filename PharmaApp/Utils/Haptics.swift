import UIKit
import CoreHaptics

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if targetEnvironment(simulator)
        // Evita errori CHHaptic sul Simulator
        return
        #else
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            let gen = UIImpactFeedbackGenerator(style: style)
            gen.impactOccurred()
        }
        #endif
    }
}

