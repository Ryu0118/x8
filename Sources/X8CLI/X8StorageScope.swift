import X8Storage

/// Keeps a client's ownership separate from the protocols served by the CLI.
struct X8StorageScope: Sendable {
    let casStore: any CASStore
    let actionCacheStore: any ActionCacheStore
    let administration: (any CacheAdministration)?
    let referenceReader: (any CASReferenceReader)?
    let retentionStore: (any CASRetentionStore)?
    private let shutdown: @Sendable () async throws -> Void

    init<Storage: CASStore & ActionCacheStore>(
        storage: Storage,
        shutdown: @escaping @Sendable (Storage) async throws -> Void
    ) {
        casStore = storage
        actionCacheStore = storage
        administration = storage as? any CacheAdministration
        referenceReader = storage as? any CASReferenceReader
        retentionStore = storage as? any CASRetentionStore
        self.shutdown = { try await shutdown(storage) }
    }

    func withStorage<Result: Sendable>(
        _ operation: @Sendable (X8StorageScope) async throws -> Result
    ) async throws -> Result {
        let result: Result
        do {
            try Task.checkCancellation()
            result = try await operation(self)
        } catch {
            // Cleanup cannot replace the operation's failure or cancellation.
            try? await shutdown()
            throw error
        }
        try await shutdown()
        return result
    }

    func casStore(role: CacheRole) -> any CASStore {
        let writable: any CASStore = role.contains(.producer)
            ? casStore : ConsumerOnlyCASStore(wrapping: casStore)
        return role.contains(.consumer) ? writable : ProducerOnlyCASStore(wrapping: writable)
    }

    func actionCacheStore(role: CacheRole) -> any ActionCacheStore {
        let writable: any ActionCacheStore = role.contains(.producer)
            ? actionCacheStore : ConsumerOnlyActionCacheStore(wrapping: actionCacheStore)
        return role.contains(.consumer) ? writable : ProducerOnlyActionCacheStore(wrapping: writable)
    }
}
