import X8Core

/// Forwards writes and returns cache misses for reads without accessing the wrapped store.
///
/// This is an implementation detail of role enforcement applied by `X8CLI`;
/// storage backends do not construct it directly.
package struct ProducerOnlyCASStore: CASStore {
    private let wrapped: any CASStore

    /// Wraps an existing store, permitting only its write operations.
    package init(wrapping wrapped: any CASStore) {
        self.wrapped = wrapped
    }

    /// Returns a cache miss without performing I/O.
    package func get(id _: CASDataID) async throws -> CASObject? {
        nil
    }

    /// Forwards the object unchanged, preserving streaming and cancellation.
    package func put(_ object: CASObject) async throws -> CASDataID {
        try await wrapped.put(object)
    }

    /// Returns a cache miss without performing I/O.
    package func load(id _: CASDataID) async throws -> ByteStream? {
        nil
    }

    /// Forwards the stream unchanged, preserving streaming and cancellation.
    package func save(_ bytes: ByteStream) async throws -> CASDataID {
        try await wrapped.save(bytes)
    }
}
