import Foundation
import SwiftUI
import Observation
import AppKit

@MainActor
@Observable
final class MacHostManager {
    var connectionStatus: String = "Starting…"
    var isAccessibilityTrusted: Bool = false
    var accessibilityStatusMessage: String = "Permission not requested yet."
    var isScrollingEnabled: Bool = true
    var lastCommandSummary: String = "—"
    
    /// Current pairing request awaiting user response
    var pendingPairingRequest: DeviceInfo?
    var showPairingAlert: Bool = false
    
    /// List of approved devices
    var approvedDevices: [DeviceInfo] { Defaults[.approvedDevices] }
    
    /// Connected clients info
    var connectedClients: [ConnectedClient] {
        Array(networkListener.connectedClients.values)
    }
    
    /// This Mac's name
    var macName: String {
        get { DeviceIdentity.getDeviceName() }
        set { DeviceIdentity.setDeviceName(newValue) }
    }

    private let accessibility = AccessibilityPermissionManager()
    private let networkListener = MacScrollNetworkListener()
    private let scrollExecutor = MacScrollExecutor()
    private var pairingResponseCallback: ((Bool) -> Void)?

    init() {
        // Generate device ID on first launch
        _ = DeviceIdentity.getOrCreateDeviceID()
        
        refreshAccessibilityState()
        setupNetworkListener()
        startListening()
    }

    // MARK: - Network setup

    private func setupNetworkListener() {
        networkListener.onStateChanged = { [weak self] in
            Task { @MainActor [weak self] in self?.refreshConnectionStatus() }
        }
        refreshConnectionStatus()
        
        // Handle pairing requests
        networkListener.onPairingRequest = { [weak self] deviceInfo, callback in
            Task { @MainActor [weak self] in
                self?.pendingPairingRequest = deviceInfo
                self?.pairingResponseCallback = callback
                self?.showPairingAlert = true
            }
        }

        // Hot path: network queue → executor queue directly, no MainActor hop.
        // UI summary update is detached at background priority.
        networkListener.onCommandReceived = { [weak self] command in
            guard let self else { return }

            // Execute immediately — no actor switch needed, executor is queue-confined
            if self.isScrollingEnabled && self.isAccessibilityTrusted {
                self.scrollExecutor.executeScrollCommand(command)
            }

            Task.detached(priority: .background) { @MainActor [weak self] in
                self?.isAccessibilityTrusted = self?.accessibility.refreshTrusted() ?? false
                self?.lastCommandSummary = "Seq \(command.sequence)  Δ\(String(format: "%.3f", command.delta))"
            }
        }
    }

    private func refreshConnectionStatus() {
        let clients = networkListener.connectedClients
        let pairedCount = clients.values.filter { $0.isPaired }.count
        
        if !networkListener.isListening {
            connectionStatus = "Not listening"
        } else if pairedCount == 0 {
            connectionStatus = "Listening – no clients"
        } else if pairedCount == 1 {
            if let client = clients.values.first(where: { $0.isPaired }),
               let name = client.deviceInfo?.name {
                connectionStatus = "Connected to \(name)"
            } else {
                connectionStatus = "1 client connected"
            }
        } else {
            connectionStatus = "\(pairedCount) clients connected"
        }
    }
    
    // MARK: - Pairing
    
    func approvePairing() {
        pairingResponseCallback?(true)
        pairingResponseCallback = nil
        pendingPairingRequest = nil
        showPairingAlert = false
    }
    
    func rejectPairing() {
        pairingResponseCallback?(false)
        pairingResponseCallback = nil
        pendingPairingRequest = nil
        showPairingAlert = false
    }
    
    func unpairDevice(_ device: DeviceInfo) {
        networkListener.unpairDevice(device.id)
    }

    // MARK: - Public API

    func startListening()  { networkListener.startListening() }
    func stopListening()   { networkListener.stopListening() }

    func refreshAccessibilityState() {
        isAccessibilityTrusted = accessibility.refreshTrusted()
        accessibilityStatusMessage = isAccessibilityTrusted
            ? "Accessibility permission granted."
            : "Permission required: enable Scroll in Privacy & Security → Accessibility."
    }

    func openAccessibilitySettings() {
        accessibility.promptForTrustIfNeeded()
        if !accessibility.openSettings() {
            accessibilityStatusMessage = "Could not open System Settings. Open Privacy & Security → Accessibility manually."
        }
        refreshAccessibilityState()
        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshAccessibilityState()
        }
    }
}
