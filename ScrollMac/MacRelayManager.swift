import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class MacHostManager {
    var connectionStatus: String = "Starting…"
    var isAccessibilityTrusted: Bool = false
    var accessibilityStatusMessage: String = "Permission not requested yet."
    var isScrollingEnabled: Bool = true
    var lastCommandSummary: String = "—"

    private let accessibility = AccessibilityPermissionManager()
    private let networkListener = MacScrollNetworkListener()
    private let scrollExecutor = MacScrollExecutor()

    init() {
        refreshAccessibilityState()
        setupNetworkListener()
        startListening()
        observeSettingsChanges()
    }

    private func observeSettingsChanges() {
        // Observe settings changes from UserDefaults
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scrollExecutor.refreshSettings()
            }
        }
    }

    private func setupNetworkListener() {
        networkListener.onStateChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshConnectionStatus()
            }
        }
        refreshConnectionStatus()

        // Handle received scroll commands
        networkListener.onCommandReceived = { [weak self] command in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Refresh trust state opportunistically.
                self.isAccessibilityTrusted = self.accessibility.refreshTrusted()

                // Execute scroll immediately if enabled
                if self.isScrollingEnabled && self.isAccessibilityTrusted {
                    self.scrollExecutor.executeScrollCommand(command)
                }

                // Update UI in background task (lower priority)
                Task.detached(priority: .background) { @MainActor [weak self] in
                    self?.lastCommandSummary = "Seq \(command.sequence), Δ\(String(format: "%.3f", command.delta)), rev \(command.settings.revision)"
                }
            }
        }
    }

    private func refreshConnectionStatus() {
        let clients = networkListener.connectedClients

        if !networkListener.isListening {
            connectionStatus = "Not listening"
        } else if clients.isEmpty {
            connectionStatus = "Listening - no clients"
        } else if clients.count == 1 {
            connectionStatus = "1 client connected"
        } else {
            connectionStatus = "\(clients.count) clients connected"
        }
    }

    func startListening() {
        networkListener.startListening()
    }

    func stopListening() {
        networkListener.stopListening()
    }

    func refreshAccessibilityState() {
        isAccessibilityTrusted = accessibility.refreshTrusted()
        accessibilityStatusMessage = isAccessibilityTrusted
            ? "Accessibility permission granted."
            : "Permission required: enable Scroll in Privacy & Security → Accessibility."
    }

    func openAccessibilitySettings() {
        accessibility.promptForTrustIfNeeded()
        let opened = accessibility.openSettings()
        if !opened {
            accessibilityStatusMessage = "Could not open System Settings automatically. Open Privacy & Security → Accessibility manually."
        }

        refreshAccessibilityState()

        Task {
            try? await Task.sleep(for: .seconds(1.0))
            await MainActor.run {
                self.refreshAccessibilityState()
            }
        }
    }
}
