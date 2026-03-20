import SwiftUI

struct SettingsView: View {
    @Environment(MacHostManager.self) private var hostManager

    var body: some View {
        @Bindable var hostManager = hostManager

        Form {
            Section("Host") {
                LabeledContent("Status", value: hostManager.connectionStatus)
                Toggle("Enable crown scrolling", isOn: $hostManager.isScrollingEnabled)
            }

            Section("Accessibility") {
                LabeledContent(
                    "Permission",
                    value: hostManager.isAccessibilityTrusted ? "Granted" : "Not granted"
                )

                Text(hostManager.accessibilityStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Refresh") {
                        hostManager.refreshAccessibilityState()
                    }

                    Button("Open Accessibility Settings") {
                        hostManager.openAccessibilitySettings()
                    }
                }
            }

            Section("Network") {
                Text("Using Network framework with Bonjour discovery")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Listening on port \(ScrollNetworkProtocol.defaultPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Service Type", value: ScrollNetworkProtocol.serviceType)
                    .font(.caption)
            }

            Section("Diagnostics") {
                LabeledContent("Last command", value: hostManager.lastCommandSummary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 320)
    }
}
