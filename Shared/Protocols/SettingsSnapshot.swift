import Foundation
#if canImport(Defaults)
import Defaults
#endif

public struct SettingsSnapshot: Codable, Sendable {
    public let revision: Int
    public let updatedAt: TimeInterval
    public let scrollSensitivity: Double
    public let invertScrollDirection: Bool
    public let smoothingMode: ScrollSmoothingMode

    public init(
        revision: Int,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        scrollSensitivity: Double,
        invertScrollDirection: Bool,
        smoothingMode: ScrollSmoothingMode
    ) {
        self.revision = revision
        self.updatedAt = updatedAt
        self.scrollSensitivity = scrollSensitivity
        self.invertScrollDirection = invertScrollDirection
        self.smoothingMode = smoothingMode
    }
}

public extension SettingsSnapshot {
#if canImport(Defaults)
    static func fromDefaults() -> SettingsSnapshot {
        SettingsSnapshot(
            revision: Defaults[.settingsRevision],
            scrollSensitivity: Defaults[.scrollSensitivity],
            invertScrollDirection: Defaults[.invertScrollDirection],
            smoothingMode: Defaults[.smoothingMode]
        )
    }

    func applyToDefaults(ifNewerThan currentRevision: Int) {
        guard revision > currentRevision else { return }

        Defaults[.scrollSensitivity] = scrollSensitivity
        Defaults[.invertScrollDirection] = invertScrollDirection
        Defaults[.smoothingMode] = smoothingMode
        Defaults[.settingsRevision] = revision
    }
#endif

    static func fromUserDefaults(_ userDefaults: UserDefaults = .standard) -> SettingsSnapshot {
        let smoothingRaw = userDefaults.string(forKey: ScrollSettingsStoreKeys.smoothingMode) ?? ScrollSmoothingMode.adaptive.rawValue
        let smoothing = ScrollSmoothingMode(rawValue: smoothingRaw) ?? .adaptive

        return SettingsSnapshot(
            revision: userDefaults.integer(forKey: ScrollSettingsStoreKeys.settingsRevision),
            scrollSensitivity: userDefaults.object(forKey: ScrollSettingsStoreKeys.scrollSensitivity) as? Double ?? 1.0,
            invertScrollDirection: userDefaults.bool(forKey: ScrollSettingsStoreKeys.invertScrollDirection),
            smoothingMode: smoothing
        )
    }

    func applyToUserDefaults(
        _ userDefaults: UserDefaults = .standard,
        ifNewerThan currentRevision: Int
    ) {
        guard revision > currentRevision else { return }

        userDefaults.set(scrollSensitivity, forKey: ScrollSettingsStoreKeys.scrollSensitivity)
        userDefaults.set(invertScrollDirection, forKey: ScrollSettingsStoreKeys.invertScrollDirection)
        userDefaults.set(smoothingMode.rawValue, forKey: ScrollSettingsStoreKeys.smoothingMode)
        userDefaults.set(revision, forKey: ScrollSettingsStoreKeys.settingsRevision)
    }
}
