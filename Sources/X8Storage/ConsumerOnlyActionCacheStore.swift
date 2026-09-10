import X8Core

/// Wraps any `ActionCacheStore` and rejects writes while still permitting reads.
///
/// Used for a `consumer`-role invocation: `getValue` delegates to the
/// wrapped store unchanged, while `putValue` is rejected before any
/// network or storage I/O occurs. This is an implementation detail of role
/// enforcement applied by `X8CLI`; storage backends do not construct it directly.
package struct ConsumerOnlyActionCacheStore: ActionCacheStore {
    private let wrapped: any ActionCacheStore

    /// Wraps an existing store, permitting only its read operation.
    package init(wrapping wrapped: any ActionCacheStore) {
        self.wrapped = wrapped
    }

    /// Delegates to the wrapped store unchanged.
    package func getValue(for key: ActionCacheKey) async throws -> ActionCacheValue? {
        try await wrapped.getValue(for: key)
    }

    /// Always rejects with `CacheRoleError.writeNotAllowed`, performing no I/O.
    package func putValue(_: ActionCacheValue, for _: ActionCacheKey) async throws {
        throw CacheRoleError.writeNotAllowed
    }
}
