import X8Core

/// Wraps any `CASStore` and rejects writes while still permitting reads.
///
/// Used for a `consumer`-role invocation: reads delegate to the wrapped
/// store unchanged, while `put`/`save` are rejected before any network or
/// storage I/O occurs. This is an implementation detail of role enforcement
/// applied by `X8CLI`; storage backends do not construct it directly.
package struct ConsumerOnlyCASStore: CASStore {
    private let wrapped: any CASStore

    /// Wraps an existing store, permitting only its read operations.
    package init(wrapping wrapped: any CASStore) {
        self.wrapped = wrapped
    }

    /// Delegates to the wrapped store unchanged.
    package func get(id: CASDataID) async throws -> CASObject? {
        try await wrapped.get(id: id)
    }

    /// Always rejects with `CacheRoleError.writeNotAllowed`, performing no I/O.
    package func put(_: CASObject) async throws -> CASDataID {
        throw CacheRoleError.writeNotAllowed
    }

    /// Delegates to the wrapped store unchanged.
    package func load(id: CASDataID) async throws -> ByteStream? {
        try await wrapped.load(id: id)
    }

    /// Always rejects with `CacheRoleError.writeNotAllowed`, performing no I/O.
    package func save(_: ByteStream) async throws -> CASDataID {
        throw CacheRoleError.writeNotAllowed
    }
}
