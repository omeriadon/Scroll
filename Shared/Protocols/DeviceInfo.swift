import Foundation
#if canImport(UIKit)
	import UIKit
#endif

/// Represents a paired device's identity
public struct DeviceInfo: Codable, Sendable, Hashable, Defaults.Serializable {
	public let id: UUID
	public var name: String
	public var lastSeen: Date

	public init(id: UUID, name: String, lastSeen: Date = Date()) {
		self.id = id
		self.name = name
		self.lastSeen = lastSeen
	}
}

/// Pairing message types for the handshake protocol
public enum PairingMessageType: UInt8, Sendable {
	case request = 0x01 // iPhone → Mac: "I want to connect"
	case approved = 0x02 // Mac → iPhone: "Connection approved"
	case rejected = 0x03 // Mac → iPhone: "Connection rejected"
	case identity = 0x04 // Mac → iPhone: "Here's my identity" (for discovery)
	case unpaired = 0x05 // Either → Other: "I've unpaired you"
}

/// Wire format for pairing messages
/// offset  0 │ messageType  UInt8           (1 byte)
/// offset  1 │ deviceID     UUID bytes      (16 bytes)
/// offset 17 │ nameLength   UInt8           (1 byte)
/// offset 18 │ name         UTF8 string     (up to 64 bytes)
public struct PairingMessage: Sendable {
	public static let headerSize = 18
	public static let maxNameLength = 64
	public static let magicByte: UInt8 = 0xAA // Distinguishes pairing from scroll commands

	public let messageType: PairingMessageType
	public let deviceID: UUID
	public let deviceName: String

	public init(messageType: PairingMessageType, deviceID: UUID, deviceName: String) {
		self.messageType = messageType
		self.deviceID = deviceID
		self.deviceName = String(deviceName.prefix(Self.maxNameLength))
	}

	public func toWireData() -> Data {
		let nameData = deviceName.data(using: .utf8) ?? Data()
		let truncatedName = nameData.prefix(Self.maxNameLength)

		var buf = Data(capacity: 1 + Self.headerSize + truncatedName.count)
		buf.append(Self.magicByte) // Magic byte to identify pairing messages
		buf.append(messageType.rawValue)
		buf.append(contentsOf: withUnsafeBytes(of: deviceID.uuid) { Array($0) })
		buf.append(UInt8(truncatedName.count))
		buf.append(contentsOf: truncatedName)
		return buf
	}

	public init?(wireData: Data) {
		// Must start with magic byte and have minimum header size
		guard wireData.count >= 1 + Self.headerSize,
		      wireData[0] == Self.magicByte else { return nil }

		guard let type = PairingMessageType(rawValue: wireData[1]) else { return nil }
		messageType = type

		// Extract UUID (bytes 2-17)
		let uuidBytes = wireData[2 ..< 18]
		let uuid = uuidBytes.withUnsafeBytes { ptr -> UUID in
			var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
			withUnsafeMutableBytes(of: &bytes) { $0.copyMemory(from: ptr) }
			return UUID(uuid: bytes)
		}
		deviceID = uuid

		// Extract name
		let nameLength = Int(wireData[18])
		guard wireData.count >= 1 + Self.headerSize + nameLength else { return nil }
		let nameData = wireData[19 ..< (19 + nameLength)]
		deviceName = String(data: Data(nameData), encoding: .utf8) ?? "Unknown"
	}

	/// Check if data appears to be a pairing message (starts with magic byte)
	public static func isPairingMessage(_ data: Data) -> Bool {
		guard let firstByte = data.first else { return false }
		return firstByte == magicByte
	}
}

/// Device identity manager for generating and storing this device's ID
public enum DeviceIdentity {
	private static let deviceIDKey = "deviceUniqueID"
	private static let deviceNameKey = "deviceCustomName"

	/// Get or create this device's unique ID
	public static func getOrCreateDeviceID() -> UUID {
		if let stored = UserDefaults.standard.string(forKey: deviceIDKey),
		   let uuid = UUID(uuidString: stored)
		{
			return uuid
		}
		let newID = UUID()
		UserDefaults.standard.set(newID.uuidString, forKey: deviceIDKey)
		return newID
	}

	/// Get this device's name (custom or default)
	public static func getDeviceName() -> String {
		if let custom = UserDefaults.standard.string(forKey: deviceNameKey), !custom.isEmpty {
			return custom
		}
		return defaultDeviceName()
	}

	/// Set a custom device name
	public static func setDeviceName(_ name: String) {
		UserDefaults.standard.set(name, forKey: deviceNameKey)
	}

	/// Get the system default device name
	public static func defaultDeviceName() -> String {
		#if os(macOS)
			return Host.current().localizedName ?? "Mac"
		#else
			return UIDevice.current.name
		#endif
	}

	/// Get this device's info
	public static func currentDeviceInfo() -> DeviceInfo {
		DeviceInfo(id: getOrCreateDeviceID(), name: getDeviceName())
	}
}
