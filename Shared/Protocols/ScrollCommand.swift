import Foundation

// Wire format: 21 bytes (flat, no framing — UDP is message-framed)
// offset  0 │ sequence     Int64 big-endian  (8 bytes)
// offset  8 │ delta        Float32 LE        (4 bytes)
// offset 12 │ velocity     Float32 LE        (4 bytes)
// offset 16 │ sensitivity  Float32 LE        (4 bytes)
// offset 20 │ flags        UInt8             (1 byte)  bit0=invertDirection

public struct ScrollCommand: Sendable {
    public static let wireSize = 21

    public let sequence: Int64
    public let delta: Double
    public let velocity: Double
    public let settings: SettingsSnapshot

    public init(sequence: Int64, delta: Double, velocity: Double, settings: SettingsSnapshot) {
        self.sequence = sequence
        self.delta    = delta
        self.velocity = velocity
        self.settings = settings
    }

    public func toWireData() -> Data {
        var buf = Data(count: Self.wireSize)
        buf.withUnsafeMutableBytes { p in
            p.storeBytes(of: sequence.bigEndian,                              toByteOffset: 0,  as: Int64.self)
            p.storeBytes(of: Float(delta).bitPattern,                         toByteOffset: 8,  as: UInt32.self)
            p.storeBytes(of: Float(velocity).bitPattern,                      toByteOffset: 12, as: UInt32.self)
            p.storeBytes(of: Float(settings.scrollSensitivity).bitPattern,    toByteOffset: 16, as: UInt32.self)
            p.storeBytes(of: settings.invertScrollDirection ? UInt8(1) : 0,   toByteOffset: 20, as: UInt8.self)
        }
        return buf
    }

    public init(wireData: Data) throws {
        guard wireData.count >= Self.wireSize else { throw ScrollCommandError.invalidData }
        let seq   = wireData.withUnsafeBytes { Int64(bigEndian: $0.loadUnaligned(fromByteOffset: 0,  as: Int64.self)) }
        let d     = wireData.withUnsafeBytes { Float(bitPattern: $0.loadUnaligned(fromByteOffset: 8,  as: UInt32.self)) }
        let v     = wireData.withUnsafeBytes { Float(bitPattern: $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self)) }
        let sens  = wireData.withUnsafeBytes { Float(bitPattern: $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self)) }
        let flags = wireData[20]
        self.sequence = seq
        self.delta    = Double(d)
        self.velocity = Double(v)
        self.settings = SettingsSnapshot(
            scrollSensitivity:      Double(sens),
            invertScrollDirection:  flags & 1 != 0
        )
    }
}

public enum ScrollCommandError: Error { case invalidData }
