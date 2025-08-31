import UIKit
import AudioToolbox

class FeedbackManager {
    static let shared = FeedbackManager()

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)

    private init() {
        impactGenerator.prepare()
    }

    func triggerFeedback(soundEnabled: Bool) {
        // Trigger haptic feedback
        impactGenerator.impactOccurred()

        // Trigger a standard system sound only if enabled
        if soundEnabled {
            AudioServicesPlaySystemSound(1104)
        }
    }
}
