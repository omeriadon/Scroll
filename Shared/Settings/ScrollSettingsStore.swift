import Foundation

#if canImport(Defaults)
import Defaults
#endif

public enum ScrollSettingsStore {
    public static var sensitivity: Double {
        get {
#if canImport(Defaults)
            Defaults[.scrollSensitivity]
#else
            UserDefaults.standard.object(forKey: ScrollSettingsStoreKeys.scrollSensitivity) as? Double ?? 1.0
#endif
        }
        set {
            let value = max(0.2, min(3.0, newValue))
#if canImport(Defaults)
            Defaults[.scrollSensitivity] = value
#else
            UserDefaults.standard.set(value, forKey: ScrollSettingsStoreKeys.scrollSensitivity)
#endif
        }
    }

    public static var invertDirection: Bool {
        get {
#if canImport(Defaults)
            Defaults[.invertScrollDirection]
#else
            UserDefaults.standard.bool(forKey: ScrollSettingsStoreKeys.invertScrollDirection)
#endif
        }
        set {
#if canImport(Defaults)
            Defaults[.invertScrollDirection] = newValue
#else
            UserDefaults.standard.set(newValue, forKey: ScrollSettingsStoreKeys.invertScrollDirection)
#endif
        }
    }

    public static var smoothingMode: ScrollSmoothingMode {
        get {
#if canImport(Defaults)
            Defaults[.smoothingMode]
#else
            let raw = UserDefaults.standard.string(forKey: ScrollSettingsStoreKeys.smoothingMode) ?? ScrollSmoothingMode.adaptive.rawValue
            return ScrollSmoothingMode(rawValue: raw) ?? .adaptive
#endif
        }
        set {
#if canImport(Defaults)
            Defaults[.smoothingMode] = newValue
#else
            UserDefaults.standard.set(newValue.rawValue, forKey: ScrollSettingsStoreKeys.smoothingMode)
#endif
        }
    }

    public static var settingsRevision: Int {
        get {
#if canImport(Defaults)
            Defaults[.settingsRevision]
#else
            UserDefaults.standard.integer(forKey: ScrollSettingsStoreKeys.settingsRevision)
#endif
        }
        set {
#if canImport(Defaults)
            Defaults[.settingsRevision] = newValue
#else
            UserDefaults.standard.set(newValue, forKey: ScrollSettingsStoreKeys.settingsRevision)
#endif
        }
    }
}
