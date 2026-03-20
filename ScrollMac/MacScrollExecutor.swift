import Foundation
import CoreGraphics
import AppKit

@MainActor
public final class MacScrollExecutor {
    private static let scrollPixelScaleFactor: Double = 85.0
    private static let animationRateHz: Double = 120.0
    private static let maxPixelsPerTick: Double = 10.0
    private static let idleStopSeconds: TimeInterval = 0.8
    private static let resetSequenceThreshold: Int64 = 1_000
    private static let resetLowSequenceCutoff: Int64 = 12

    private var lastSequence: Int64 = 0
    private var lastTimestamp: TimeInterval = 0
    private var lastIntentTimestamp: TimeInterval = 0

    // Incoming command budget in pixel-space, consumed by local animator.
    private var accumulatedPixelBudget: Double = 0
    private var pendingPixelRemainder: Double = 0

    private var animatorTask: Task<Void, Never>?
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    public init() {
    }

    public func refreshSettings() {
        // Kept for API compatibility with existing callers.
        // Settings are now streamed from iPhone inside each command packet.
    }

    public func executeScrollCommand(_ command: ScrollCommand) {
        // Skip out-of-order commands, but allow a fresh iPhone session reset.
        if command.sequence <= lastSequence {
            let sequenceDelta = lastSequence - command.sequence
            let isLikelyNewSession =
                command.sequence <= Self.resetLowSequenceCutoff &&
                sequenceDelta >= Self.resetSequenceThreshold &&
                command.timestamp > lastTimestamp

            guard isLikelyNewSession else { return }

            // Reset local execution state for clean continuation.
            accumulatedPixelBudget = 0
            pendingPixelRemainder = 0
        }

        lastSequence = command.sequence
        lastTimestamp = command.timestamp
        lastIntentTimestamp = Date().timeIntervalSinceReferenceDate

        // Apply settings bundled with this command (iPhone is source of truth)
        var finalDelta = command.delta * command.settings.scrollSensitivity
        if command.settings.invertScrollDirection {
            finalDelta = -finalDelta
        }

        // Convert to pixel budget and let local animator smooth/schedule events.
        accumulatedPixelBudget += finalDelta * Self.scrollPixelScaleFactor
        startAnimatorIfNeeded()
    }

    private func startAnimatorIfNeeded() {
        guard animatorTask == nil else { return }

        animatorTask = Task { [weak self] in
            guard let self else { return }

            let frameDurationNs = UInt64(1_000_000_000.0 / Self.animationRateHz)

            while !Task.isCancelled {
                await self.tickAnimator()
                try? await Task.sleep(nanoseconds: frameDurationNs)
            }
        }
    }

    private func stopAnimatorIfIdle() {
        let now = Date().timeIntervalSinceReferenceDate
        let isIdleByTime = now - lastIntentTimestamp > Self.idleStopSeconds
        let isIdleByBudget = abs(accumulatedPixelBudget) < 0.001 && abs(pendingPixelRemainder) < 0.001

        guard isIdleByTime && isIdleByBudget else { return }

        animatorTask?.cancel()
        animatorTask = nil
    }

    private func tickAnimator() {
        guard accumulatedPixelBudget != 0 || pendingPixelRemainder != 0 else {
            stopAnimatorIfIdle()
            return
        }

        let clampedStep = accumulatedPixelBudget.clamped(
            min: -Self.maxPixelsPerTick,
            max: Self.maxPixelsPerTick
        )
        accumulatedPixelBudget -= clampedStep

        let totalPixelsThisTick = clampedStep + pendingPixelRemainder
        let quantizedPixels = Int(totalPixelsThisTick.rounded(.towardZero))
        pendingPixelRemainder = totalPixelsThisTick - Double(quantizedPixels)

        guard quantizedPixels != 0 else {
            stopAnimatorIfIdle()
            return
        }

        postScrollPixels(quantizedPixels)
        stopAnimatorIfIdle()
    }

    private func postScrollPixels(_ quantizedPixels: Int) {
        let wheelDelta = Int32(-quantizedPixels) // Negative for natural scrolling

        let pixelEvent = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: wheelDelta,
            wheel2: 0,
            wheel3: 0
        )

        if let pixelEvent {
            pixelEvent.post(tap: .cghidEventTap)
        } else {
            let lineEvent = CGEvent(
                scrollWheelEvent2Source: eventSource,
                units: .line,
                wheelCount: 1,
                wheel1: wheelDelta,
                wheel2: 0,
                wheel3: 0
            )
            lineEvent?.post(tap: .cghidEventTap)
        }
    }

    deinit {
        animatorTask?.cancel()
    }
}

private extension Double {
    func clamped(min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, self))
    }
}
