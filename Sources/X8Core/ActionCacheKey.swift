import Foundation

/// An opaque binary key for one Xcode compilation action's cached result.
///
/// Xcode uses this key with `KeyValueDB`. X8 preserves its exact bytes and
/// does not interpret or recalculate the key. It identifies an action-cache
/// record, not a project, source file, CAS object, or provider object key.
public struct ActionCacheKey: Hashable, Sendable {
    /// The exact bytes supplied by the cache protocol.
    public let rawValue: Data

    /// Creates a key without interpreting or transforming its bytes.
    public init(rawValue: Data) {
        self.rawValue = rawValue
    }
}
