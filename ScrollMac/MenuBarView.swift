import AppKit
import SwiftUI

struct MenuBarView: View {
	@Environment(MacHostManager.self) private var hostManager
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		@Bindable var hostManager = hostManager

		VStack(alignment: .leading, spacing: 12) {
			Text("Scroll Host")
				.font(.headline)

			Label(hostManager.connectionStatus, systemImage: "antenna.radiowaves.left.and.right")
				.foregroundStyle(.secondary)

			Label(
				hostManager.isAccessibilityTrusted ? "Accessibility Enabled" : "Accessibility Required",
				systemImage: hostManager.isAccessibilityTrusted ? "checkmark.shield" : "exclamationmark.triangle"
			)
			.foregroundStyle(hostManager.isAccessibilityTrusted ? .green : .orange)

			Divider()

			Toggle("Enable crown scrolling", isOn: $hostManager.isScrollingEnabled)

			Divider()

			if !hostManager.isAccessibilityTrusted {
				VStack(alignment: .leading, spacing: 8) {
					Text("⚠️ Accessibility permission is required")
						.foregroundStyle(.orange)
						.font(.caption)

					Button("Open Accessibility Settings") {
						hostManager.openAccessibilitySettings()
					}
					.buttonStyle(.borderedProminent)
				}
			} else {
				Text("✓ Ready to receive scroll commands")
					.foregroundStyle(.green)
					.font(.caption)
			}

			Button("Open Settings") {
				AppDelegate.shared?.showSettings()
				//                openWindow(id: "scroll-settings")
				//                NSApp.activate(ignoringOtherApps: true)
				//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				//                    for window in NSApp.windows where window.identifier?.rawValue == "scroll-settings" {
				//                        window.makeKeyAndOrderFront(nil)
				//                        break
				//                    }
				//                }
			}
			.keyboardShortcut(",", modifiers: .command)
			.buttonStyle(.bordered)
		}
		.padding(14)
		.frame(width: 360)
	}
}
