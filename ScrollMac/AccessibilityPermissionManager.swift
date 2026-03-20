import ApplicationServices
import AppKit
import Foundation

@MainActor
final class AccessibilityPermissionManager {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func refreshTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func promptForTrustIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func openSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        let systemSettingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if NSWorkspace.shared.open(systemSettingsURL) {
            return true
        }

        return false
    }
}
