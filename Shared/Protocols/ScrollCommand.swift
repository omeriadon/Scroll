import Foundation

public struct ScrollCommand: Codable, Sendable {
    public static let currentProtocolVersion: UInt8 = 2

    public let protocolVersion: UInt8
    public let sequence: Int64
    public let delta: Double
    public let velocity: Double
    public let timestamp: TimeInterval
    public let settings: SettingsSnapshot

    public init(
        protocolVersion: UInt8 = ScrollCommand.currentProtocolVersion,
        sequence: Int64,
        delta: Double,
        velocity: Double,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        settings: SettingsSnapshot
    ) {
        self.protocolVersion = protocolVersion
        self.sequence = sequence
        self.delta = delta
        self.velocity = velocity
        self.timestamp = timestamp
        self.settings = settings
    }
}

public extension ScrollCommand {
    // Compact binary encoding for minimal latency over network
    // Format:
    // [version:1][sequence:8][delta:8][velocity:8][timestamp:8]
    // [settingsRevision:8][settingsUpdatedAt:8][scrollSensitivity:8]
    // [invertScrollDirection:1][smoothingMode:1]
    // Total = 59 bytes
    func toBinaryData() -> Data {
        var data = Data(capacity: 59)

        // Version (1 byte)
        data.append(protocolVersion)

        // Sequence (8 bytes, big endian)
        withUnsafeBytes(of: sequence.bigEndian) { data.append(contentsOf: $0) }

        // Delta (8 bytes, IEEE 754 double)
        withUnsafeBytes(of: delta) { data.append(contentsOf: $0) }

        // Velocity (8 bytes, IEEE 754 double)
        withUnsafeBytes(of: velocity) { data.append(contentsOf: $0) }

        // Timestamp (8 bytes, IEEE 754 double)
        withUnsafeBytes(of: timestamp) { data.append(contentsOf: $0) }

        // Settings revision (8 bytes, big endian)
        let revision = Int64(settings.revision)
        withUnsafeBytes(of: revision.bigEndian) { data.append(contentsOf: $0) }

        // Settings updatedAt (8 bytes, IEEE 754 double)
        withUnsafeBytes(of: settings.updatedAt) { data.append(contentsOf: $0) }

        // Scroll sensitivity (8 bytes, IEEE 754 double)
        withUnsafeBytes(of: settings.scrollSensitivity) { data.append(contentsOf: $0) }

        // Invert direction (1 byte)
        data.append(settings.invertScrollDirection ? 1 : 0)

        // Smoothing mode (1 byte)
        switch settings.smoothingMode {
        case .adaptive:
            data.append(0)
        case .linear:
            data.append(1)
        }

        print(
            "📦 Encode ScrollCommand " +
            "v=\(protocolVersion) seq=\(sequence) bytes=\(data.count) " +
            "delta=\(delta) velocity=\(velocity) " +
            "rev=\(settings.revision) sens=\(settings.scrollSensitivity) " +
            "invert=\(settings.invertScrollDirection) smooth=\(settings.smoothingMode.rawValue)"
        )

        return data
    }

    init(binaryData: Data) throws {
        let versionByte = binaryData.first.map(String.init) ?? "nil"
        print("📥 Decode attempt payload=\(binaryData.count) versionByte=\(versionByte)")

        guard binaryData.count >= 33 else {
            print("❌ Decode rejected: payload too small for legacy minimum (33)")
            throw ScrollCommandError.invalidBinaryData
        }

        func readInt64BigEndian(at offset: Int) -> Int64 {
            var value: Int64 = 0
            _ = withUnsafeMutableBytes(of: &value) { rawBuffer in
                binaryData.copyBytes(to: rawBuffer, from: offset..<(offset + 8))
            }
            return Int64(bigEndian: value)
        }

        func readDouble(at offset: Int) -> Double {
            var value: Double = 0
            _ = withUnsafeMutableBytes(of: &value) { rawBuffer in
                binaryData.copyBytes(to: rawBuffer, from: offset..<(offset + 8))
            }
            return value
        }

        func readUInt8(at offset: Int) -> UInt8 {
            binaryData[offset]
        }

        var offset = 0

        // Version
        let version = binaryData[offset]
        offset += 1

        // Sequence
        let sequence = readInt64BigEndian(at: offset)
        offset += 8

        // Delta
        let delta = readDouble(at: offset)
        offset += 8

        // Velocity
        let velocity = readDouble(at: offset)
        offset += 8

        // Timestamp
        let timestamp = readDouble(at: offset)
        offset += 8

        // Legacy payload (v1): [version][sequence][delta][velocity][timestamp] (33 bytes)
        if version < 2 {
            print("ℹ️ Decoding legacy command format (v\(version), 33-byte baseline)")
            let settings = SettingsSnapshot(
                revision: 0,
                updatedAt: timestamp,
                scrollSensitivity: 1.0,
                invertScrollDirection: false,
                smoothingMode: .adaptive
            )

            self.init(
                protocolVersion: version,
                sequence: sequence,
                delta: delta,
                velocity: velocity,
                timestamp: timestamp,
                settings: settings
            )
            return
        }

        guard binaryData.count >= 59 else {
            print("❌ Decode rejected: v2+ payload too small (need >=59, got \(binaryData.count))")
            throw ScrollCommandError.invalidBinaryData
        }

        // Settings revision
        let revisionRaw = readInt64BigEndian(at: offset)
        offset += 8

        // Settings updated at
        let settingsUpdatedAt = readDouble(at: offset)
        offset += 8

        // Settings sensitivity
        let sensitivity = readDouble(at: offset)
        offset += 8

        // Invert direction
        let invertDirection = readUInt8(at: offset) != 0
        offset += 1

        // Smoothing mode
        let smoothingRaw = readUInt8(at: offset)
        let smoothingMode: ScrollSmoothingMode = smoothingRaw == 1 ? .linear : .adaptive

        let settings = SettingsSnapshot(
            revision: max(Int(revisionRaw), 0),
            updatedAt: settingsUpdatedAt,
            scrollSensitivity: sensitivity,
            invertScrollDirection: invertDirection,
            smoothingMode: smoothingMode
        )

        self.init(
            protocolVersion: version,
            sequence: sequence,
            delta: delta,
            velocity: velocity,
            timestamp: timestamp,
            settings: settings
        )

        print(
            "✅ Decode success " +
            "v=\(version) seq=\(sequence) bytes=\(binaryData.count) " +
            "delta=\(delta) velocity=\(velocity) " +
            "rev=\(settings.revision) sens=\(settings.scrollSensitivity) " +
            "invert=\(settings.invertScrollDirection) smooth=\(settings.smoothingMode.rawValue)"
        )
    }
}

public enum ScrollCommandError: Error {
    case encodingFailed
    case invalidBinaryData
}
