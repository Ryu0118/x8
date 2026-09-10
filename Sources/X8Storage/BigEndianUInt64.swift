import Foundation

/// Encodes fixed-width big-endian integers shared by storage formats.
///
/// The helper owns only the byte-order primitive used by versioned envelopes;
/// it does not define an envelope schema or perform bounds validation for a
/// particular backend.
package enum BigEndianUInt64 {
    /// Appends one unsigned 64-bit integer in network byte order.
    package static func append(_ value: UInt64, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    /// Decodes exactly one unsigned 64-bit integer in network byte order.
    package static func decode(_ data: Data) -> UInt64? {
        guard data.count == MemoryLayout<UInt64>.size else { return nil }
        return data.reduce(UInt64.zero) { value, byte in
            value * 256 + UInt64(byte)
        }
    }
}
