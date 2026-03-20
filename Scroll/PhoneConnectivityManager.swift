import Foundation
import Network
import Observation

@MainActor
@Observable
final class PhoneConnectivityManager {
    static let shared = PhoneConnectivityManager()

    private(set) var lastCommand: ScrollCommand?
    private(set) var droppedCommandCount: Int = 0

    private var nextSequence: Int64 = 1
    private let networkClient = iPhoneScrollNetworkClient()
    private var pendingDelta: Double = 0
    private var pendingVelocityTotal: Double = 0
    private var pendingSampleCount: Int = 0
    private var flushTask: Task<Void, Never>?
    private var lastSendTimestamp: TimeInterval = 0

    private init() {
        networkClient.startDiscovery()
    }

    var macConnectionStatus: String {
        if networkClient.isConnected, let name = networkClient.currentHostName {
            return "Connected to \(name)"
        } else if networkClient.isConnected {
            return "Connected to Mac"
        } else {
            return "Not connected"
        }
    }

    var discoveredHosts: [NWBrowser.Result] {
        networkClient.discoveredHosts
    }

    func connectToHost(_ result: NWBrowser.Result) {
        networkClient.connectToHost(result)
    }

    func disconnect() {
        flushTask?.cancel()
        flushTask = nil
        clearPendingSamples()
        networkClient.disconnect()
    }

    var isConnectedToMac: Bool {
        networkClient.isConnected
    }

    func currentSettingsSnapshot() -> SettingsSnapshot {
        SettingsSnapshot.fromUserDefaults()
    }

    func updateSettings(
        sensitivity: Double,
        inverted: Bool,
        smoothingMode: ScrollSmoothingMode
    ) {
        ScrollSettingsStore.sensitivity = sensitivity
        ScrollSettingsStore.invertDirection = inverted
        ScrollSettingsStore.smoothingMode = smoothingMode
        ScrollSettingsStore.settingsRevision += 1
    }

    func updatePerformanceSettings(
        inputResolution: ScrollInputResolution,
        maxSendRateHz: Double
    ) {
        ScrollSettingsStore.inputResolution = inputResolution
        ScrollSettingsStore.maxSendRateHz = maxSendRateHz
    }

    func sendScrollDelta(delta: Double, velocity: Double) {
        pendingDelta += delta
        pendingVelocityTotal += velocity
        pendingSampleCount += 1

        let now = Date().timeIntervalSinceReferenceDate
        let minInterval = 1.0 / max(30.0, ScrollSettingsStore.maxSendRateHz)
        let elapsed = now - lastSendTimestamp

        if elapsed >= minInterval {
            flushPendingCommand()
        } else {
            scheduleFlush(after: minInterval - elapsed)
        }
    }

    private func scheduleFlush(after delaySeconds: TimeInterval) {
        guard delaySeconds > 0 else {
            flushPendingCommand()
            return
        }

        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            await MainActor.run {
                self?.flushPendingCommand()
            }
        }
    }

    private func flushPendingCommand() {
        flushTask?.cancel()
        flushTask = nil

        guard pendingSampleCount > 0 else { return }

        let sequence = nextSequence
        nextSequence += 1

        let mergedDelta = pendingDelta
        let mergedVelocity = pendingVelocityTotal / Double(pendingSampleCount)

        clearPendingSamples()

        let command = ScrollCommand(
            sequence: sequence,
            delta: mergedDelta,
            velocity: mergedVelocity,
            settings: currentSettingsSnapshot()
        )

        lastSendTimestamp = Date().timeIntervalSinceReferenceDate
        lastCommand = command
        networkClient.sendCommand(command)
    }

    private func clearPendingSamples() {
        pendingDelta = 0
        pendingVelocityTotal = 0
        pendingSampleCount = 0
    }
}
