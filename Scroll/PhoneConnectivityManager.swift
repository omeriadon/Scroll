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

    func sendScrollDelta(delta: Double, velocity: Double) {
        let sequence = nextSequence
        nextSequence += 1

        let command = ScrollCommand(
            sequence: sequence,
            delta: delta,
            velocity: velocity,
            settings: currentSettingsSnapshot()
        )

        lastCommand = command
        networkClient.sendCommand(command)
    }
}
