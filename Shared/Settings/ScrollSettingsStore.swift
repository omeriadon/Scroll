import Foundation

public enum ScrollSettingsStore {
    public static var sensitivity: Double {
        get { Defaults[.scrollSensitivity] }
        set { Defaults[.scrollSensitivity] = max(0.2, min(3.0, newValue)) }
    }

    public static var invertDirection: Bool {
        get { Defaults[.invertScrollDirection] }
        set { Defaults[.invertScrollDirection] = newValue }
    }

    public static var smoothingMode: ScrollSmoothingMode {
        get { Defaults[.smoothingMode] }
        set { Defaults[.smoothingMode] = newValue }
    }

    public static var inputResolution: ScrollInputResolution {
        get { Defaults[.inputResolution] }
        set { Defaults[.inputResolution] = newValue }
    }

    public static var maxSendRateHz: Double {
        get { Defaults[.maxSendRateHz] }
        set { Defaults[.maxSendRateHz] = max(30.0, min(120.0, newValue)) }
    }
}
