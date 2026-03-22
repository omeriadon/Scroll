import Foundation

public struct SettingsSnapshot: Sendable {
	public let scrollSensitivity: Double
	public let invertScrollDirection: Bool

	public init(scrollSensitivity: Double, invertScrollDirection: Bool) {
		self.scrollSensitivity = scrollSensitivity
		self.invertScrollDirection = invertScrollDirection
	}

	public static func current() -> SettingsSnapshot {
		SettingsSnapshot(
			scrollSensitivity: Defaults[.scrollSensitivity],
			invertScrollDirection: Defaults[.invertScrollDirection]
		)
	}
}
