import X8Core

/// Stores opaque result metadata for Xcode compilation actions.
///
/// The key and entry bytes are supplied by Xcode's `KeyValueDB` protocol. A
/// conforming store must preserve them without interpreting the action or
/// reconstructing its key. A missing value is a cache miss (`nil`); provider
/// failures remain thrown errors so a frontend can choose its fail-open policy.
public protocol ActionCacheStore: Sendable {
    /// Returns the value for a key, or `nil` when the key is missing.
    func getValue(for key: ActionCacheKey) async throws -> ActionCacheValue?

    /// Replaces the value associated with a key.
    func putValue(_ value: ActionCacheValue, for key: ActionCacheKey) async throws
}
