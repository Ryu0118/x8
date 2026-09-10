import Foundation

/// Opaque result metadata stored for one Action Cache key.
///
/// This is the `KeyValueDB` entries map, not the compiled bytes themselves. An
/// entry such as `value` may contain serialized metadata referring to CAS
/// identifiers, so X8 preserves entry names and bytes without interpreting
/// them. The value is not a CAS payload and does not imply that its referenced
/// objects are safe to delete without a separate retention policy.
public struct ActionCacheValue: Equatable, Sendable {
    /// The entries, preserving each value as the bytes provided by the cache protocol.
    public let entries: [String: Data]

    /// Creates an Action Cache value from its opaque entries.
    public init(entries: [String: Data]) {
        self.entries = entries
    }
}
