import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class MacHostManager {
    var connectionStatus:       String = "Starting…"
    var isAccessibilityTrusted: Bool   = false
    var accessibilityStatusMessage: String = "Permission not requested yet."
    var isScrollingEnabled: Bool = true
    var lastCommandSummary: String = "—"

    private let accessibility    = AccessibilityPermissionManager()
    private let networkListener  = MacScrollNetworkListener()
    private let scrollExecutor   = MacScrollExecutor()

    init() {
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
        let n = networkListener.connectedClients.count
        if !networkListener.isListening {
            connectionStatus = "Not listening"
        } else if n == 0 {
            connectionStatus = "Listening – no clients"
        } else {
            connectionStatus = n == 1 ? "1 client connected" : "\(n) clients connected"
        }
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
