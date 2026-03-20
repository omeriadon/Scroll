import Foundation

public enum ScrollSmoothingMode: String, Codable, Sendable {
    case adaptive
    case linear
}

public enum ScrollInputResolution: String, Codable, Sendable, CaseIterable {
    case precise
    case balanced
    case smooth

    public var quantizationStep: Double {
        switch self {
        case .precise:
            return 0.0015
        case .balanced:
            return 0.0035
        case .smooth:
            return 0.007
        }
    }

    public var displayName: String {
        switch self {
        case .precise:
            return "PRECISE"
        case .balanced:
            return "BALANCED"
        case .smooth:
            return "SMOOTH"
        }
    }
}

public enum ScrollSettingsStoreKeys {
    public static let scrollSensitivity = "scrollSensitivity"
    public static let invertScrollDirection = "invertScrollDirection"
    public static let smoothingMode = "smoothingMode"
    public static let inputResolution = "inputResolution"
    public static let maxSendRateHz = "maxSendRateHz"
    public static let settingsRevision = "settingsRevision"
}

#if canImport(Defaults)
import Defaults

extension ScrollSmoothingMode: Defaults.Serializable {}
extension ScrollInputResolution: Defaults.Serializable {}

public extension Defaults.Keys {
    static let scrollSensitivity = Key<Double>(ScrollSettingsStoreKeys.scrollSensitivity, default: 1.0)
    static let invertScrollDirection = Key<Bool>(ScrollSettingsStoreKeys.invertScrollDirection, default: false)
    static let smoothingMode = Key<ScrollSmoothingMode>(ScrollSettingsStoreKeys.smoothingMode, default: .adaptive)
    static let inputResolution = Key<ScrollInputResolution>(ScrollSettingsStoreKeys.inputResolution, default: .balanced)
    static let maxSendRateHz = Key<Double>(ScrollSettingsStoreKeys.maxSendRateHz, default: 90.0)
    static let settingsRevision = Key<Int>(ScrollSettingsStoreKeys.settingsRevision, default: 0)
}
#endif
