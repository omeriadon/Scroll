import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
final class ScrollPadViewModel {
    var touchLocation: CGPoint?

    private var lastTranslationY: CGFloat = 0
    private var lastSampleTime: TimeInterval = Date().timeIntervalSinceReferenceDate

    func beginInteraction(at point: CGPoint) {
        touchLocation = point
        lastTranslationY = 0
        lastSampleTime = Date().timeIntervalSinceReferenceDate
    }

    func updateInteraction(
        location: CGPoint,
        translationY: CGFloat,
        sendScroll: (_ delta: Double, _ velocity: Double) -> Void
    ) {
        touchLocation = location

        let now = Date().timeIntervalSinceReferenceDate
        let timeDelta = max(now - lastSampleTime, 0.001)

        let incrementalTranslation = translationY - lastTranslationY
        lastTranslationY = translationY
        lastSampleTime = now

        // Convert points to a normalized gesture delta.
        let delta = Double(incrementalTranslation / 90.0)

        // Velocity normalized to delta units per second.
        let velocity = delta / timeDelta

        guard abs(delta) > 0.0001 else { return }
        sendScroll(delta, velocity)
    }

    func endInteraction() {
        touchLocation = nil
        lastTranslationY = 0
    }
}
