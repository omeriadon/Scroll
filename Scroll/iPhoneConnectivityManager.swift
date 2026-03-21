import Foundation
import Network
import Observation
import QuartzCore

@MainActor
@Observable
final class PhoneConnectivityManager {
	static let shared = PhoneConnectivityManager()

	private(set) var lastCommand: ScrollCommand?
	private(set) var wasUnpaired = false // Flag to show unpaired alert

	private var nextSequence: Int64 = 1
	private let networkClient = iPhoneScrollNetworkClient()

	// Accumulator — merged when rate gate opens
	private var pendingDelta: Double = 0
	private var pendingVelocityTotal: Double = 0
	private var pendingSampleCount: Int = 0
	private var lastSendTime: Double = 0 // CACurrentMediaTime

	/// This device's name
	var deviceName: String {
		get { DeviceIdentity.getDeviceName() }
		set { DeviceIdentity.setDeviceName(newValue) }
	}

	private init() {
		networkClient.startDiscovery()
		networkClient.onUnpaired = { [weak self] _ in
			self?.wasUnpaired = true
		}
	}

	// MARK: - Public API

	var macConnectionStatus: String {
		if networkClient.isPaired, let name = networkClient.currentHostName {
			return name
		} else if pairingState == .rejected {
			return "Rejected"
		} else if networkClient.isConnected, !networkClient.isPaired {
			return "Pairing..."
		} else {
			return "Not Connected"
		}
	}

	var pairingState: DiscoveredMac.PairingState {
		networkClient.pairingState
	}

	var discoveredHosts: [DiscoveredMac] {
		networkClient.discoveredHosts
	}

	var isConnectedToMac: Bool {
		networkClient.isPaired
	}

	var currentMac: DiscoveredMac? {
		networkClient.currentMac
	}

	var lastConnectedMac: DeviceInfo? {
		Defaults[.lastConnectedMac]
	}

	func checkAutoConnect() {
		networkClient.checkAutoConnect()
	}

	func clearUnpairedFlag() {
		wasUnpaired = false
	}

	func connectToHost(_ result: NWBrowser.Result) {
		networkClient.connectToHost(result)
	}

	func disconnect() {
		clearPending()
		networkClient.disconnect()
	}

	func forgetLastMac() {
		clearPending()
		networkClient.forgetLastMac()
	}

	func updateSettings(sensitivity: Double, inverted: Bool, smoothingMode: ScrollSmoothingMode) {
		Defaults[.scrollSensitivity] = max(0.2, min(3.0, sensitivity))
		Defaults[.invertScrollDirection] = inverted
		Defaults[.smoothingMode] = smoothingMode
	}

	func updatePerformanceSettings(inputResolution: ScrollInputResolution, maxSendRateHz: Double) {
		Defaults[.inputResolution] = inputResolution
		Defaults[.maxSendRateHz] = max(30.0, min(120.0, maxSendRateHz))
	}

	/// Called from gesture .onChanged
	func sendScrollDelta(delta: Double, velocity: Double) {
		pendingDelta += delta
		pendingVelocityTotal += velocity
		pendingSampleCount += 1

		let now = CACurrentMediaTime()
		let minGap = 1.0 / max(30.0, Defaults[.maxSendRateHz])

		guard now - lastSendTime >= minGap else { return }
		flush()
	}

	/// Called from gesture .onEnded — guarantees last sample is never silently dropped
	func flushIfPending() {
		guard pendingSampleCount > 0 else { return }
		flush()
	}

	// MARK: - Private

	private func flush() {
		guard pendingSampleCount > 0 else { return }

		let cmd = ScrollCommand(
			sequence: nextSequence,
			delta: pendingDelta,
			velocity: pendingVelocityTotal / Double(pendingSampleCount),
			settings: .current()
		)
		nextSequence += 1
		lastSendTime = CACurrentMediaTime()
		lastCommand = cmd
		clearPending()
		networkClient.sendCommand(cmd)
	}

	private func clearPending() {
		pendingDelta = 0
		pendingVelocityTotal = 0
		pendingSampleCount = 0
	}
}
