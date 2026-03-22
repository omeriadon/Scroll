import Luminare
import SwiftUI

struct SettingsView: View {
	@Environment(MacHostManager.self) private var hostManager
	@State private var showNameAlert = false
	@State private var editingName: String = ""

	var body: some View {
		@Bindable var hostManager = hostManager

		Form {
			Section("This Mac") {
				HStack {
					Text("Name")
					Spacer()
					Text(hostManager.macName)
						.foregroundStyle(.secondary)
					Button("Edit") {
						editingName = hostManager.macName
						showNameAlert = true
					}
					.buttonStyle(.bordered)
				}

				LabeledContent("Status", value: hostManager.connectionStatus)
				Toggle("Enable crown scrolling", isOn: $hostManager.isScrollingEnabled)
			}

			Section("Paired Device") {
				if let device = hostManager.approvedDevices.first {
					HStack {
						VStack(alignment: .leading) {
							Text(device.name)
								.font(.body)
							Text(formatLastSeen(device.lastSeen))
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Button("Unpair", role: .destructive) {
							hostManager.unpairDevice(device)
						}
						.buttonStyle(.bordered)
					}
				} else {
					Text("No device paired")
						.foregroundStyle(.secondary)
						.italic()
				}
			}

			Section("Accessibility") {
				LabeledContent(
					"Permission",
					value: hostManager.isAccessibilityTrusted ? "Granted" : "Not granted"
				)

				Text(hostManager.accessibilityStatusMessage)
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
		}
		//		.listStyle(.bordered)
		//		.padding(.bottom, 2)
		//		.background { HideScrollIndicators() }
		//		.scrollDisabled(true)
		.formStyle(.grouped)
		.alert("Mac Name", isPresented: $showNameAlert) {
			TextField("Name", text: $editingName)
			Button("Cancel", role: .cancel) {}
			Button("Save") {
				let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
				if !trimmed.isEmpty {
					hostManager.macName = trimmed
				}
			}
		} message: {
			Text("Enter a name for this Mac")
		}
	}

	private func formatLastSeen(_ date: Date) -> String {
		let interval = Date().timeIntervalSince(date)
		if interval < 60 {
			return "Just now"
		} else if interval < 3600 {
			let minutes = Int(interval / 60)
			return "\(minutes) min ago"
		} else {
			return date.formatted(.relative(presentation: .named))
		}
	}
}

struct HideScrollIndicators: NSViewRepresentable {
	func makeNSView(context _: Context) -> NSView {
		let view = NSView()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			hideScrollers(in: view.window?.contentView)
		}
		return view
	}

	func updateNSView(_: NSView, context _: Context) {}

	private func hideScrollers(in view: NSView?) {
		guard let view else { return }
		if let scrollView = view as? NSScrollView {
			scrollView.verticalScroller?.isHidden = true
			scrollView.horizontalScroller?.isHidden = true
		}
		for subview in view.subviews {
			hideScrollers(in: subview)
		}
	}
}
