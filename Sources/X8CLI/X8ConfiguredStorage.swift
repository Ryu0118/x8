/// Captures one resolved configuration and its still-unopened storage factory.
struct X8ConfiguredStorage: Sendable {
    let configuration: X8CLIConfiguration<Void>
    let openStorage: @Sendable () async throws -> X8StorageScope

    func withStorage<Result: Sendable>(
        _ operation: @Sendable (X8StorageScope) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        let storage = try await openStorage()
        return try await storage.withStorage(operation)
    }
}
