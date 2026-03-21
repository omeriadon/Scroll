import AppKit
import SwiftUI

@main
struct ScrollMacApp: App {
	@State private var hostManager = MacHostManager()
	@Environment(\.openWindow) private var openWindow

	var body: some Scene {
		MenuBarExtra("Scroll", systemImage: "digitalcrown.horizontal.press") {
			MenuBarView()
				.environment(hostManager)
		}
		.menuBarExtraStyle(.window)
		.onChange(of: hostManager.showPairingAlert) { _, showAlert in
			if showAlert {
				Task { @MainActor in
					openWindow(id: "pairing-request")
					NSApp.activate(ignoringOtherApps: true)
				}
			}
		}

		Window("Settings", id: "scroll-settings") {
			SettingsView()
				.environment(hostManager)
		}
		.windowResizability(.contentSize)
		.commands {
			CommandGroup(replacing: .appSettings) {
				Button("Settings...") {
					openWindow(id: "scroll-settings")
					NSApp.activate(ignoringOtherApps: true)
				}
				.keyboardShortcut(",", modifiers: .command)
			}
		}

		Window("Pairing Request", id: "pairing-request") {
			PairingRequestView()
				.background {
					WindowConfigurator()
				}
				.environment(hostManager)
		}
		.windowStyle(.plain)
		.windowResizability(.contentSize)
		.defaultPosition(.center)
	}
}

struct PairingRequestView: View {
	@Environment(MacHostManager.self) private var hostManager
	@Environment(\.dismissWindow) private var dismissWindow

	var body: some View {
		VStack(spacing: 7) {
			Image(systemName: "iphone.radiowaves.left.and.right")
				.font(.system(size: 50))
				.foregroundStyle(.tint)

			if let device = hostManager.pendingPairingRequest {
				Text("Pairing Request")
					.font(.title)
					.bold()

				Spacer()
					.frame(height: 20)

				Text("\"\(device.name)\" wants to connect")
					.font(.headline)

				Text("Allow this device to send scroll commands?")
					.foregroundStyle(.secondary)

				Spacer()
					.frame(height: 20)
			}

			HStack(spacing: 16) {
				Button("Deny") {
					hostManager.rejectPairing()
					dismissWindow(id: "pairing-request")
				}
				.buttonStyle(.glass)
				.keyboardShortcut(.escape, modifiers: [])
				.controlSize(.extraLarge)
				.buttonBorderShape(.roundedRectangle)

				Button("Allow") {
					hostManager.approvePairing()
					dismissWindow(id: "pairing-request")
				}
				.keyboardShortcut(.return, modifiers: [])
				.buttonStyle(.glassProminent)
				.controlSize(.extraLarge)
				.buttonBorderShape(.roundedRectangle)
			}
		}
		.fontDesign(.monospaced)
		.padding(30)
		.frame(minWidth: 400)
		.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
	}
}

struct WindowConfigurator: NSViewRepresentable {
	func makeNSView(context: Context) -> NSView {
		let view = NSView()
		DispatchQueue.main.async {
			guard let w = view.window else { return }
			object_setClass(w, KeyableWindow.self)
			w.makeKeyAndOrderFront(nil)
			w.orderFrontRegardless()
			w.isOpaque = false
			w.backgroundColor = .clear
			w.hasShadow = false
			w.isMovableByWindowBackground = true
			w.level = .floating
			w.contentView?.wantsLayer = true
			w.contentView?.layer?.cornerRadius = 30
			w.contentView?.layer?.masksToBounds = true
		}
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyableWindow: NSWindow {
	override var canBecomeKey: Bool {
		true
	}

	override var canBecomeMain: Bool {
		true
	}
}
