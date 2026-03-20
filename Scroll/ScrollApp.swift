import SwiftUI

@main
struct ScrollApp: App {
    @State private var connectivityManager = PhoneConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectivityManager)
        }
    }
}

