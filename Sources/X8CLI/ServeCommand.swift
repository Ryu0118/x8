import ArgumentParser
import Darwin
import Foundation
import X8Kit
import X8Storage

struct ServeCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run a standalone Xcode cache proxy.",
        subcommands: [ServeStopCommand.self]
    )

    @Flag(
        name: [.short, .customLong("detach")],
        help: "Run the cache proxy in the background and return once it is ready."
    )
    var detach = false

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

    /// Marks this invocation as the detached child spawned by `-d`/`--detach`.
    ///
    /// The value is the fixed descriptor number
    /// (`PosixServeProcessLauncher.readinessFileDescriptor`) the child writes
    /// its readiness byte to; it is passed through `argv` rather than the
    /// environment so it survives regardless of what the parent's `--detach`
    /// flow chooses to forward. It is undocumented and never meant to be
    /// typed by a person.
    @Option(name: .customLong("child-ready-fd"), help: .hidden)
    var childReadyFileDescriptor: Int32?

    func run(context: X8CommandContext) async throws {
        guard let childReadyFileDescriptor else {
            try await (detach ? runDetachedParent(context: context) : runForeground(context: context))
            return
        }
        try await runChild(context: context, readyFileDescriptor: childReadyFileDescriptor)
    }

    /// Runs the cache proxy in the foreground, streaming events until terminated.
    private func runForeground(context: X8CommandContext) async throws {
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

    /// Runs as the detached child: starts the server, signals readiness, then waits.
    ///
    /// The child claims its own pidfile through `XcodeServeRunner`, using its
    /// own process record, rather than the parent pre-writing one — see
    /// `XcodeServeRunner.claimPIDFile` for why this ordering is load-bearing.
    /// Standard output here is the redirected `serve.log`, so this path prints
    /// nothing beyond what a foreground run would already log.
    private func runChild(context: X8CommandContext, readyFileDescriptor: Int32) async throws {
        let configured = try await context.loadConfiguration()
        let configuration = configured.configuration
        try await configured.withStorage { storage in
            let executablePath = Self.resolvedExecutablePath()
            let processRecord = LiveProcessLivenessProbe.currentProcessRecord(executablePath: executablePath)
            let runner = XcodeServeRunner(
                socketPath: XcodeServeRunner.defaultSocketPath(profileID: configuration.profileID),
                casStore: storage.casStore(role: configuration.role),
                actionCacheStore: storage.actionCacheStore(role: configuration.role),
                workingDirectory: Self.workingDirectory(from: workspaceDirectory),
                livenessProbe: LiveProcessLivenessProbe(),
                processRecord: processRecord
            )
            let handle = try await runner.start()
            context.logger.info(
                "✅ Cache server is ready at \(handle.socketPath).",
                metadata: .color(.green)
            )
            Self.signalReadiness(on: readyFileDescriptor)
            let streamingTask = Self.streamEvents(from: handle, output: context.output)
            defer { streamingTask.cancel() }
            try await handle.waitForTerminationSignal()
        }
    }

    /// Runs as the parent of `-d`/`--detach`: spawns the child, waits for readiness, then exits.
    private func runDetachedParent(context: X8CommandContext) async throws {
        let configured = try await context.loadConfiguration()
        let profileID = configured.configuration.profileID
        let logFileURL = XcodeServeRunner.defaultLogFileURL(profileID: profileID)
        // The child creates this directory too, once it starts, but the log
        // file must already have somewhere to live before it is spawned.
        try FileManager.default.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try ServeDaemonSupport.rotateLog(at: logFileURL)

        var readinessPipe = try ServeReadinessPipe()
        let plan = ServeProcessLaunchPlan(
            executablePath: Self.resolvedExecutablePath(),
            arguments: Self.childArguments(
                workspaceDirectory: workspaceDirectory,
                readyFileDescriptor: PosixServeProcessLauncher.readinessFileDescriptor
            ),
            environment: ProcessInfo.processInfo.environment,
            stdioLogURL: logFileURL,
            readinessWriteFileDescriptor: readinessPipe.childWriteFileDescriptor
        )
        let pid = try PosixServeProcessLauncher().launch(plan)
        readinessPipe.closeWriteEnd()

        let outcome = try await readinessPipe.waitForReadiness(
            pid: pid,
            timeout: .seconds(30),
            signaling: LiveProcessSignaling()
        )
        try Self.report(outcome, profileID: profileID, logFileURL: logFileURL, context: context)
    }

    private static func report(
        _ outcome: ServeReadinessOutcome,
        profileID: String,
        logFileURL: URL,
        context: X8CommandContext
    ) throws {
        switch outcome {
        case .ready:
            let socketPath = XcodeServeRunner.defaultSocketPath(profileID: profileID)
            context.output.standardOutput(socketPath)
            context.logger.info(
                "✅ Cache server is running in the background at \(socketPath). Logs: \(logFileURL.path)",
                metadata: .color(.green)
            )
        case let .exitedBeforeReady(status):
            throw ValidationError(
                "The detached `x8 serve` process exited before becoming ready (status \(status)). " +
                    "See \(logFileURL.path) for details."
            )
        case .timedOut:
            throw ValidationError(
                "The detached `x8 serve` process did not become ready in time and was killed. " +
                    "See \(logFileURL.path) for details."
            )
        }
    }

    private static func workingDirectory(from path: String?) -> URL {
        URL(
            filePath: path ?? FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory
        )
    }

    /// Builds the child's `argv`, reusing this invocation's flags plus the hidden readiness marker.
    private static func childArguments(workspaceDirectory: String?, readyFileDescriptor: Int32) -> [String] {
        var arguments = ["serve", "--child-ready-fd", String(readyFileDescriptor)]
        if let workspaceDirectory {
            arguments += ["--workspace-directory", workspaceDirectory]
        }
        return arguments
    }

    /// Writes the single readiness byte and closes the descriptor.
    ///
    /// This descriptor was dup2'd by the launcher from the parent's pipe, so
    /// closing it here is what lets the parent observe EOF/readiness.
    private static func signalReadiness(on fileDescriptor: Int32) {
        var byte: UInt8 = 1
        _ = withUnsafeBytes(of: &byte) { write(fileDescriptor, $0.baseAddress, 1) }
        close(fileDescriptor)
    }

    private static func resolvedExecutablePath() -> String {
        Bundle.main.executableURL?.resolvingSymlinksInPath().path
            ?? CommandLine.arguments[0]
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
