import X8Storage

/// Preserves the relationship between a caller's configuration and storage types.
struct X8ConfigurationResolution<Value: Sendable, Storage: CASStore & ActionCacheStore>: Sendable {
    let configuration: @Sendable () async throws -> X8CLIConfiguration<Value>
    let storage: @Sendable (Value) async throws -> Storage
    let shutdown: @Sendable (Storage) async throws -> Void

    func resolve() async throws -> X8ConfiguredStorage {
        let resolved = try await configuration()
        let metadata = try resolved.metadata()
        return X8ConfiguredStorage(configuration: metadata) {
            try await X8StorageScope(storage: storage(resolved.value), shutdown: shutdown)
        }
    }
}
