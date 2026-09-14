import ArgumentParser
import Foundation
import X8Kit
import X8Storage

struct ServeCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run a standalone Xcode cache proxy."
    )

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: "Print the cache settings to add to Xcode."
    )
    var printCacheSettings = true

    @Flag(name: .long, help: "Print only the socket path and keep serving.")
    var printSocket = false

    @Option(
        name: .long,
        help: "Physical workspace directory to map to /^workspace. Defaults to the current directory."
    )
    var workspaceDirectory: String?

    func run(context: X8CommandContext) async throws {
        let configured = try await context.loadConfiguration()
        let configuration = configured.configuration
        try await configured.withStorage { storage in
            let runner = XcodeServeRunner(
                socketPath: XcodeServeRunner.defaultSocketPath(profileID: configuration.profileID),
                casStore: storage.casStore(role: configuration.role),
                actionCacheStore: storage.actionCacheStore(role: configuration.role),
                workingDirectory: Self.workingDirectory(from: workspaceDirectory)
            )
            let handle = try await runner.start()
            Self.writeSettings(
                for: handle,
                printCacheSettings: printCacheSettings,
                printSocket: printSocket,
                output: context.output
            )
            context.logger.info(
                "✅ Cache server is ready at \(handle.socketPath).",
                metadata: .color(.green)
            )
            if let warning = handle.eventsSocketWarning {
                context.logger.warning(
                    "Live cache-events socket unavailable: \(warning). `x8 tail` will not connect.",
                    metadata: .color(.yellow)
                )
            }
            let streamingTask = Self.streamEvents(from: handle, output: context.output)
            defer { streamingTask.cancel() }
            try await handle.waitForTerminationSignal()
        }
    }

    private static func workingDirectory(from path: String?) -> URL {
        URL(
            filePath: path ?? FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory
        )
    }

    /// Streams live cache events to `output`, the same rendering `x8 tail` uses.
    ///
    /// Subscribes in-process through the handle's broadcaster rather than
    /// dialing the events socket, so this works even when that socket failed
    /// to start.
    private static func streamEvents(from handle: XcodeServeHandle, output: X8CLIOutput) -> Task<Void, Never> {
        Task {
            for await event in await handle.subscribeToEvents() {
                output.standardOutput(TailLineFormatter.render(X8CacheEventLine.line(for: event)))
            }
        }
    }

    private static func writeSettings(
        for handle: XcodeServeHandle,
        printCacheSettings: Bool,
        printSocket: Bool,
        output: X8CLIOutput
    ) {
        if printSocket {
            output.standardOutput(handle.socketPath)
            return
        }
        guard printCacheSettings else { return }
        handle.cacheEnvironment
            .sorted { $0.key < $1.key }
            .forEach { output.standardOutput("\($0.key)=\($0.value)") }
    }
}
