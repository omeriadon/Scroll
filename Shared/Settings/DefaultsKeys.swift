import Foundation

public enum ScrollSmoothingMode: String, Codable, Sendable {
    case adaptive
    case linear
}

public enum ScrollSettingsStoreKeys {
    public static let scrollSensitivity = "scrollSensitivity"
    public static let invertScrollDirection = "invertScrollDirection"
    public static let smoothingMode = "smoothingMode"
    public static let settingsRevision = "settingsRevision"
}

#if canImport(Defaults)
import Defaults

extension ScrollSmoothingMode: Defaults.Serializable {}

public extension Defaults.Keys {
    static let scrollSensitivity = Key<Double>(ScrollSettingsStoreKeys.scrollSensitivity, default: 1.0)
    static let invertScrollDirection = Key<Bool>(ScrollSettingsStoreKeys.invertScrollDirection, default: false)
    static let smoothingMode = Key<ScrollSmoothingMode>(ScrollSettingsStoreKeys.smoothingMode, default: .adaptive)
    static let settingsRevision = Key<Int>(ScrollSettingsStoreKeys.settingsRevision, default: 0)
}
#endif
