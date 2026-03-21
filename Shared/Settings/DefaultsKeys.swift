import Foundation

public enum ScrollSmoothingMode: String, Codable, Sendable, CaseIterable, Defaults.Serializable {
    case adaptive
    case linear
}

public enum ScrollInputResolution: String, Codable, Sendable, CaseIterable, Defaults.Serializable {
    case precise
    case balanced
    case smooth

    public var quantizationStep: Double {
        switch self {
        case .precise:  return 0.0015
        case .balanced: return 0.0035
        case .smooth:   return 0.007
        }
    }

    public var displayName: String {
        switch self {
        case .precise:  return "Precise"
        case .balanced: return "Balanced"
        case .smooth:   return "Smooth"
        }
    }
}

public extension Defaults.Keys {
    // Scroll settings
    static let scrollSensitivity     = Key<Double>("scrollSensitivity",          default: 1.0)
    static let invertScrollDirection = Key<Bool>("invertScrollDirection",         default: false)
    static let smoothingMode         = Key<ScrollSmoothingMode>("smoothingMode", default: .linear)
    static let inputResolution       = Key<ScrollInputResolution>("inputResolution", default: .smooth)
    static let maxSendRateHz         = Key<Double>("maxSendRateHz",               default: 90.0)
    
    // Device pairing (Mac-side)
    static let approvedDevices       = Key<[DeviceInfo]>("approvedDevices",       default: [])
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding",       default: false)
    
    // Device pairing (iPhone-side)
    static let lastConnectedMac      = Key<DeviceInfo?>("lastConnectedMac",       default: nil)
    static let autoConnectEnabled    = Key<Bool>("autoConnectEnabled",            default: true)
}
