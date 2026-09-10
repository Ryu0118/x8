import ArgumentParser
import Darwin
import X8Storage

/// Runs x8's command interface with caller-owned configuration and storage.
///
/// Construction performs no I/O. Each invocation resolves configuration at
/// most once and opens storage only when its selected command needs it.
public struct X8CLI: Sendable {
    private let configuration: @Sendable () async throws -> X8ConfiguredStorage
    var output = X8CLIOutput.live

    /// Connects a configuration loader, storage factory, and optional cleanup.
    ///
    /// The loader must not contact a remote service. The factory owns cleanup
    /// if it fails before returning; after it returns, the CLI calls `shutdown`
    /// exactly once after all command operations have stopped. Closures must
    /// preserve cancellation, and owned clients must supply a shutdown closure.
    public init<Value: Sendable, Storage: CASStore & ActionCacheStore>(
        configuration: @escaping @Sendable () async throws -> X8CLIConfiguration<Value>,
        storage: @escaping @Sendable (Value) async throws -> Storage,
        shutdown: @escaping @Sendable (Storage) async throws -> Void = { _ in }
    ) {
        let resolution = X8ConfigurationResolution(
            configuration: configuration,
            storage: storage,
            shutdown: shutdown
        )
        self.configuration = { try await resolution.resolve() }
    }

    /// Executes a command and returns its process status without calling exit.
    ///
    /// A nil argument list reads process arguments. Help, version, and completion
    /// requests bypass configuration. Diagnostics retain ArgumentParser's
    /// status and stream conventions; child process statuses are preserved.
    public func run(arguments: [String]? = nil) async -> Int32 {
        do {
            try await execute(arguments: arguments)
            return 0
        } catch {
            return report(error)
        }
    }

    /// Runs the CLI, completes cleanup, and terminates the process with its status.
    public func main(arguments: [String]? = nil) async {
        let status = await run(arguments: arguments)
        Darwin.exit(status)
    }

    /// Keeps configuration commands available in an executable built without storage.
    package init(
        configuration: @escaping @Sendable () async throws -> X8CLIConfiguration<some Sendable>,
        storageUnavailable message: String
    ) {
        self.configuration = {
            let resolved = try await configuration()
            return try X8ConfiguredStorage(configuration: resolved.metadata()) {
                throw ValidationError(message)
            }
        }
    }

    private func execute(arguments: [String]?) async throws {
        var command = try X8RootCommand.parseAsRoot(arguments)
        guard let executable = command as? any X8ExecutableCommand else {
            try command.run()
            return
        }
        let context = X8CommandContext(loadConfiguration: configuration, output: output)
        try await executable.run(context: context)
    }

    private func report(_ error: any Error) -> Int32 {
        let status = X8RootCommand.exitCode(for: error).rawValue
        let message = X8RootCommand.fullMessage(for: error)
        guard !message.isEmpty else { return status }
        let write = status == 0 ? output.standardOutput : output.standardError
        write(message)
        return status
    }
}
