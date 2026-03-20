import Foundation
import CoreGraphics
import AppKit

@MainActor
public final class MacScrollExecutor {
    private static let scrollPixelScaleFactor: Double = 85.0
    private static let maxScrollPixelsPerEvent: Int = 18
    private static let resetSequenceThreshold: Int64 = 1_000
    private static let resetLowSequenceCutoff: Int64 = 12

    private var lastSequence: Int64 = 0
    private var lastTimestamp: TimeInterval = 0
    private var pendingPixelRemainder: Double = 0

    public init() {
    }

    public func refreshSettings() {
        // Kept for API compatibility with existing callers.
        // Settings are now streamed from iPhone inside each command packet.
    }

    public func executeScrollCommand(_ command: ScrollCommand) {
        print(
            "🖥️ [EXEC] recv seq=\(command.sequence) delta=\(command.delta) " +
            "sens=\(command.settings.scrollSensitivity) inv=\(command.settings.invertScrollDirection)"
        )

        // Skip out-of-order commands, but allow a fresh iPhone session reset.
        if command.sequence <= lastSequence {
            let sequenceDelta = lastSequence - command.sequence
            let isLikelyNewSession =
                command.sequence <= Self.resetLowSequenceCutoff &&
                sequenceDelta >= Self.resetSequenceThreshold &&
                command.timestamp > lastTimestamp

            guard isLikelyNewSession else {
                print(
                    "🖥️ [EXEC] drop out-of-order seq=\(command.sequence) " +
                    "last=\(lastSequence) delta=\(sequenceDelta)"
                )
                return
            }

            // Reset local execution state for clean continuation.
            pendingPixelRemainder = 0
            print("🖥️ [EXEC] accepted new session reset seq=\(command.sequence)")
        }

        lastSequence = command.sequence
        lastTimestamp = command.timestamp

        // Apply settings bundled with this command (iPhone is source of truth)
        var finalDelta = command.delta * command.settings.scrollSensitivity
        if command.settings.invertScrollDirection {
            finalDelta = -finalDelta
        }
        print("🖥️ [EXEC] finalDelta=\(finalDelta)")

        // Convert delta to scroll pixels and preserve fractional remainder.
        let totalPixels = (finalDelta * Self.scrollPixelScaleFactor) + pendingPixelRemainder
        let quantizedPixels = Int(totalPixels.rounded(.towardZero))
        pendingPixelRemainder = totalPixels - Double(quantizedPixels)
        print(
            "🖥️ [EXEC] totalPixels=\(totalPixels) quantized=\(quantizedPixels) " +
            "remainder=\(pendingPixelRemainder)"
        )

        // Don't emit zero-value wheel events.
        guard quantizedPixels != 0 else {
            print("🖥️ [EXEC] skip: quantized is zero")
            return
        }

        let direction = quantizedPixels > 0 ? 1 : -1
        var remainingMagnitude = abs(quantizedPixels)

        // Break large deltas into smaller packets for smoother, more natural movement.
        while remainingMagnitude > 0 {
            let step = min(remainingMagnitude, Self.maxScrollPixelsPerEvent)
            let wheelDelta = Int32(-direction * step) // Negative for natural scrolling
            print("🖥️ [EXEC] step=\(step) wheelDelta=\(wheelDelta)")

            let source = CGEventSource(stateID: .hidSystemState)
            let pixelEvent = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: wheelDelta,
                wheel2: 0,
                wheel3: 0
            )

            if let pixelEvent {
                pixelEvent.post(tap: .cghidEventTap)
                print("🖥️ [EXEC] posted pixel event")
            } else {
                print("🖥️ [EXEC] pixel event creation failed, trying line units")
                let lineEvent = CGEvent(
                    scrollWheelEvent2Source: source,
                    units: .line,
                    wheelCount: 1,
                    wheel1: wheelDelta,
                    wheel2: 0,
                    wheel3: 0
                )
                lineEvent?.post(tap: .cghidEventTap)
                print("🖥️ [EXEC] posted line event fallback=\(lineEvent != nil)")
            }

            remainingMagnitude -= step
        }

        print("🖥️ [EXEC] command complete seq=\(command.sequence)")
    }
}
