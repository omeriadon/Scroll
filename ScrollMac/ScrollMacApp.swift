import SwiftUI
import AppKit
import UserNotifications

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
                openWindow(id: "pairing-request")
                NSApp.activate(ignoringOtherApps: true)
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
                .environment(hostManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct PairingRequestView: View {
    @Environment(MacHostManager.self) private var hostManager
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            if let device = hostManager.pendingPairingRequest {
                Text("Pairing Request")
                    .font(.headline)
                
                Text("\"\(device.name)\" wants to connect")
                    .font(.body)
                
                Text("Allow this device to send scroll commands?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 16) {
                Button("Deny") {
                    hostManager.rejectPairing()
                    dismissWindow(id: "pairing-request")
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Allow") {
                    hostManager.approvePairing()
                    dismissWindow(id: "pairing-request")
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 300)
    }
}
