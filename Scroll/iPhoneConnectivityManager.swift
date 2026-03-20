import Foundation
import Network
import Observation
import QuartzCore

@MainActor
@Observable
final class PhoneConnectivityManager {
	static let shared = PhoneConnectivityManager()

	private(set) var lastCommand: ScrollCommand?

	private var nextSequence: Int64 = 1
	private let networkClient = iPhoneScrollNetworkClient()

	// Accumulator — merged when rate gate opens
	private var pendingDelta:         Double = 0
	private var pendingVelocityTotal: Double = 0
	private var pendingSampleCount:   Int    = 0
	private var lastSendTime:         Double = 0   // CACurrentMediaTime

	private init() {
		networkClient.startDiscovery()
	}

	// MARK: - Public API

	var macConnectionStatus: String {
		if networkClient.isConnected, let name = networkClient.currentHostName {
			return "Connected"
		} else if networkClient.isConnected {
			return "Connected"
		} else {
			return "Not Connected"
		}
	}

	var discoveredHosts: [NWBrowser.Result] { networkClient.discoveredHosts }
	var isConnectedToMac: Bool              { networkClient.isConnected }

	func connectToHost(_ result: NWBrowser.Result) { networkClient.connectToHost(result) }

	func disconnect() {
		clearPending()
		networkClient.disconnect()
	}

	func updateSettings(sensitivity: Double, inverted: Bool, smoothingMode: ScrollSmoothingMode) {
		Defaults[.scrollSensitivity]     = max(0.2, min(3.0, sensitivity))
		Defaults[.invertScrollDirection] = inverted
		Defaults[.smoothingMode]         = smoothingMode
	}

	func updatePerformanceSettings(inputResolution: ScrollInputResolution, maxSendRateHz: Double) {
		Defaults[.inputResolution] = inputResolution
		Defaults[.maxSendRateHz]   = max(30.0, min(120.0, maxSendRateHz))
	}

	// Called from gesture .onChanged
	func sendScrollDelta(delta: Double, velocity: Double) {
		pendingDelta         += delta
		pendingVelocityTotal += velocity
		pendingSampleCount   += 1

		let now      = CACurrentMediaTime()
		let minGap   = 1.0 / max(30.0, Defaults[.maxSendRateHz])

		guard now - lastSendTime >= minGap else { return }
		flush()
	}

	// Called from gesture .onEnded — guarantees last sample is never silently dropped
	func flushIfPending() {
		guard pendingSampleCount > 0 else { return }
		flush()
	}

	// MARK: - Private

	private func flush() {
		guard pendingSampleCount > 0 else { return }

		let cmd = ScrollCommand(
			sequence: nextSequence,
			delta:    pendingDelta,
			velocity: pendingVelocityTotal / Double(pendingSampleCount),
			settings: .current()
		)
		nextSequence += 1
		lastSendTime = CACurrentMediaTime()
		lastCommand  = cmd
		clearPending()
		networkClient.sendCommand(cmd)
	}

	private func clearPending() {
		pendingDelta         = 0
		pendingVelocityTotal = 0
		pendingSampleCount   = 0
	}
}

