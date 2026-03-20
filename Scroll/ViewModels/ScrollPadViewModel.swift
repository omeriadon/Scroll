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
        minimumDeltaStep: Double,
        sendScroll: (_ delta: Double, _ velocity: Double) -> Void
    ) {
        touchLocation = location

        let now = Date().timeIntervalSinceReferenceDate
        let timeDelta = max(now - lastSampleTime, 0.001)

        let incrementalTranslation = translationY - lastTranslationY
        lastTranslationY = translationY
        lastSampleTime = now

        // Convert points to a normalized gesture delta.
        let rawDelta = Double(incrementalTranslation / 90.0)
        let step = max(minimumDeltaStep, 0.0005)
        let delta = (rawDelta / step).rounded(.toNearestOrAwayFromZero) * step

        // Velocity normalized to delta units per second.
        let velocity = delta / timeDelta

        guard abs(delta) >= step else { return }
        sendScroll(delta, velocity)
    }

    func endInteraction() {
        touchLocation = nil
        lastTranslationY = 0
    }
}
