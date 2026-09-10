import X8Core

/// Forwards writes and returns cache misses for reads without accessing the wrapped store.
///
/// This is an implementation detail of role enforcement applied by `X8CLI`;
/// storage backends do not construct it directly.
package struct ProducerOnlyActionCacheStore: ActionCacheStore {
    private let wrapped: any ActionCacheStore

    /// Wraps an existing store, permitting only its write operation.
    package init(wrapping wrapped: any ActionCacheStore) {
        self.wrapped = wrapped
    }

    /// Returns a cache miss without performing I/O.
    package func getValue(for _: ActionCacheKey) async throws -> ActionCacheValue? {
        nil
    }

    /// Delegates to the wrapped store unchanged.
    package func putValue(_ value: ActionCacheValue, for key: ActionCacheKey) async throws {
        try await wrapped.putValue(value, for: key)
    }
}
