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

        Window("Settings", id: "scroll-settings") {
            SettingsView()
                .environment(hostManager)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openWindow(id: "scroll-settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
