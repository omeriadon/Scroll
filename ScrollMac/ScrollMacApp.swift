import AppKit
import Luminare
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
	weak static var shared: AppDelegate?
	private var controller: NSWindowController?
	let hostManager = MacHostManager.shared

	override init() {
		super.init()
		AppDelegate.shared = self
		print("AppDelegate init")
	}

	func showSettings() {
		print("showSettings called")
		if controller == nil {
			print("creating window")
			let window = LuminareWindow {
				SettingsView()
					.environment(self.hostManager)
					.frame(width: 450, height: 600)
			}
			print("window created: \(window)")
			window.backgroundColor = .white.withAlphaComponent(0.001)
			window.ignoresMouseEvents = false
			window.delegate = self
			controller = NSWindowController(window: window)
			print("controller created: \(String(describing: controller))")
		}

		print("activation policy before: \(NSApp.activationPolicy().rawValue)")
		NSApp.setActivationPolicy(.regular)
		print("activation policy after: \(NSApp.activationPolicy().rawValue)")

		controller?.showWindow(self)
		print("showWindow called")

		controller?.window?.makeKeyAndOrderFront(nil)
		controller?.window?.orderFrontRegardless()
		print("window visible: \(String(describing: controller?.window?.isVisible))")
		print("window frame: \(String(describing: controller?.window?.frame))")

		NSApp.activate(ignoringOtherApps: true)
		print("NSApp activated")
	}

	func windowWillClose(_: Notification) {
		print("window closing")
		NSApp.setActivationPolicy(.accessory)
		controller = nil
	}
}

@main
struct ScrollMacApp: App {
	@State private var hostManager = MacHostManager.shared
	@Environment(\.openWindow) private var openWindow
	@Environment(\.dismissWindow) var dismissWindow

	@State private var isHovered = false

	@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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

		Window("Pairing Request", id: "pairing-request") {
			PairingRequestView()
				.background {
					PairingWindowConfigurator()
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
				.foregroundStyle(.white)
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

struct PairingWindowConfigurator: NSViewRepresentable {
	func makeNSView(context _: Context) -> NSView {
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

	func updateNSView(_: NSView, context _: Context) {}
}

struct SettingsWindowConfigurator: NSViewRepresentable {
	func makeNSView(context _: Context) -> NSView {
		let view = NSView()
		DispatchQueue.main.async {
			guard let w = view.window else { return }
			object_setClass(w, KeyableWindow.self)
			w.makeKeyAndOrderFront(nil)
			w.orderFrontRegardless()
			w.isOpaque = false
			w.backgroundColor = .clear
			w.hasShadow = false
			w.isMovableByWindowBackground = false
			w.level = .floating
			w.contentView?.wantsLayer = true
			w.contentView?.layer?.cornerRadius = 25
			w.contentView?.layer?.masksToBounds = true
		}
		return view
	}

	func updateNSView(_: NSView, context _: Context) {}
}

class KeyableWindow: NSWindow {
	override var canBecomeKey: Bool {
		true
	}

	override var canBecomeMain: Bool {
		true
	}
}

struct WindowDragHandle: NSViewRepresentable {
	func makeNSView(context _: Context) -> DragView {
		DragView()
	}

	func updateNSView(_: DragView, context _: Context) {}
}

class DragView: NSView {
	override func mouseDown(with event: NSEvent) {
		window?.performDrag(with: event)
	}
}
