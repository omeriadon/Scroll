import AppKit
import CoreGraphics
import Foundation

/// Runs entirely on its own high-priority queue — zero MainActor involvement on the scroll path.
public final class MacScrollExecutor {
	private static let pixelScale: Double = 85.0
	private static let maxPixelsPerTick: Double = 10.0
	private static let idleSeconds: TimeInterval = 0.8
	private static let resetLowCutoff: Int64 = 12
	private static let resetThreshold: Int64 = 1000
	/// 8 ms ≈ 120 Hz; DispatchSourceTimer is far more precise than Task.sleep
	private static let timerIntervalNs: UInt64 = 8_333_333

	private let queue = DispatchQueue(label: "com.scroll.mac.executor", qos: .userInteractive)
	private var timer: DispatchSourceTimer?

	// All state below must only be accessed on `queue`
	private var lastSequence: Int64 = 0
	private var lastIntentTime: TimeInterval = 0
	private var pixelBudget: Double = 0
	private var pixelRemainder: Double = 0
	private let eventSource = CGEventSource(stateID: .hidSystemState)

	public init() {}

	/// Can be called from any queue
	public func executeScrollCommand(_ command: ScrollCommand) {
		queue.async { [self] in _execute(command) }
	}

	// MARK: - Queue-confined implementation

	private func _execute(_ command: ScrollCommand) {
		// Out-of-order rejection with new-session exemption
		if command.sequence <= lastSequence {
			let delta = lastSequence - command.sequence
			let isNewSession = command.sequence <= Self.resetLowCutoff && delta >= Self.resetThreshold
			guard isNewSession else { return }
			pixelBudget = 0
			pixelRemainder = 0
		}

		lastSequence = command.sequence
		lastIntentTime = CACurrentMediaTime()

		var finalDelta = command.delta * command.settings.scrollSensitivity
		if command.settings.invertScrollDirection { finalDelta = -finalDelta }

		pixelBudget += finalDelta * Self.pixelScale
		startTimerIfNeeded()
	}

	private func startTimerIfNeeded() {
		guard timer == nil else { return }
		let t = DispatchSource.makeTimerSource(queue: queue)
		t.schedule(deadline: .now(), repeating: .nanoseconds(Int(Self.timerIntervalNs)), leeway: .microseconds(200))
		t.setEventHandler { [weak self] in self?.tick() }
		t.resume()
		timer = t
	}

	private func tick() {
		guard pixelBudget != 0 || pixelRemainder != 0 else {
			stopIfIdle()
			return
		}

		let step = pixelBudget.clamped(to: -Self.maxPixelsPerTick ... Self.maxPixelsPerTick)
		pixelBudget -= step

		let total = step + pixelRemainder
		let quantized = Int(total.rounded(.towardZero))
		pixelRemainder = total - Double(quantized)

		if quantized != 0 { postScroll(quantized) }
		stopIfIdle()
	}

	private func stopIfIdle() {
		let now = CACurrentMediaTime()
		let timeIdle = now - lastIntentTime > Self.idleSeconds
		let dataIdle = abs(pixelBudget) < 0.001 && abs(pixelRemainder) < 0.001
		guard timeIdle, dataIdle else { return }
		timer?.cancel()
		timer = nil
	}

	private func postScroll(_ pixels: Int) {
		let wheel = Int32(-pixels)
		if let ev = CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel,
		                    wheelCount: 1, wheel1: wheel, wheel2: 0, wheel3: 0)
		{
			ev.post(tap: .cghidEventTap)
		} else if let ev = CGEvent(scrollWheelEvent2Source: eventSource, units: .line,
		                           wheelCount: 1, wheel1: wheel, wheel2: 0, wheel3: 0)
		{
			ev.post(tap: .cghidEventTap)
		}
	}

	deinit {
		timer?.cancel()
	}
}

private extension Double {
	func clamped(to range: ClosedRange<Double>) -> Double {
		Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
	}
}
