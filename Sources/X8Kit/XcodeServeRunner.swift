import FileManagerProtocol
import Foundation
import X8Storage

/// Starts a long-lived Xcode cache proxy on a stable Unix socket.
///
/// This runner is the standalone-server entry point for clients such as
/// Xcode.app that need a stable socket rather than an invocation-scoped one.
/// `start()` creates the parent directory, refuses to replace an existing
/// socket, starts the server, waits for endpoint readiness, and returns an
/// `XcodeServeHandle`. The handle owns the running session; the server
/// remains available until the handle is shut down, its process receives a
/// termination signal, or the transport fails.
///
/// The runner does not install a supervisor or persist cache data itself. The
/// supplied storage implementations determine where CAS and Action Cache
/// records live.
package struct XcodeServeRunner: Sendable {
    private let socketPath: String
    private let casStore: any CASStore
    private let actionCacheStore: any ActionCacheStore
    private let serverFactory: XcodeCacheServerFactory
    private let serverLifecycle: XcodeCacheServerLifecycle
    private let fileManager: any FileManagerProtocolMacOS
    private let workingDirectory: URL?
    private let events: X8CacheEventBroadcaster
    private let processRecord: XcodeServeProcessRecord?

    /// Creates a standalone runner for one stable socket endpoint.
    ///
    /// - Parameters:
    ///   - socketPath: The endpoint to expose to Xcode clients.
    ///   - casStore: The provider-neutral CAS implementation.
    ///   - actionCacheStore: The provider-neutral Action Cache implementation.
    ///   - workingDirectory: The physical directory Xcode uses as the compiler
    ///     working directory. It is mapped to `/^workspace` in the returned
    ///     handle's cache settings.
    ///   - fileManager: The filesystem dependency used for the endpoint
    ///     directory and cleanup.
    ///   - metrics: The recorder receiving cache traffic observations. Every
    ///     event also becomes available to ``startEventsSocket(profileID:)``,
    ///     regardless of whether that socket is ever started.
    ///   - processRecord: Identifies the process starting this server, so its
    ///     pidfile can be claimed before binding and removed on shutdown.
    ///     `nil` (the default) skips the pidfile entirely, for a caller such
    ///     as foreground `x8 serve` that has no separate detached process to
    ///     track.
    package init(
        socketPath: String,
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        workingDirectory: URL? = nil,
        fileManager: any FileManagerProtocolMacOS = FileManager.default,
        metrics: any X8CacheMetricsRecorder = X8CacheMetricsStore(),
        processRecord: XcodeServeProcessRecord? = nil
    ) {
        let events = X8CacheEventBroadcaster(wrapping: metrics)
        self.init(
            socketPath: socketPath,
            casStore: casStore,
            actionCacheStore: actionCacheStore,
            serverFactory: XcodeCacheServer.liveFactory(metrics: events),
            workingDirectory: workingDirectory,
            fileManager: fileManager,
            events: events,
            processRecord: processRecord
        )
    }

    /// Creates a standalone server runner with an injected server factory.
    package init(
        socketPath: String,
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        serverFactory: @escaping XcodeCacheServerFactory,
        workingDirectory: URL? = nil,
        fileManager: any FileManagerProtocolMacOS = FileManager.default,
        serverLifecycle: XcodeCacheServerLifecycle? = nil,
        events: X8CacheEventBroadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore()),
        processRecord: XcodeServeProcessRecord? = nil
    ) {
        self.socketPath = socketPath
        self.casStore = casStore
        self.actionCacheStore = actionCacheStore
        self.serverFactory = serverFactory
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        self.events = events
        self.processRecord = processRecord
        self.serverLifecycle = serverLifecycle ?? XcodeCacheServerLifecycle(
            fileManager: fileManager
        )
    }

    /// Returns the stable per-user socket path for a storage profile.
    ///
    /// The path is only a naming convention; this method does not create a
    /// directory, start a server, or verify that the endpoint is unused.
    ///
    /// - Parameters:
    ///   - profileID: The caller-selected profile component used to isolate
    ///     independent cache endpoints.
    ///   - fileManager: Filesystem dependency used to resolve the application
    ///     support directory.
    package static func defaultSocketPath(
        profileID: String,
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) -> String {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        return applicationSupport
            .appending(path: "X8")
            .appending(path: profileID)
            .appending(path: XcodeCacheRuntimeDirectory.socketFileName)
            .path
    }

    /// Returns the persisted metrics file for a stable serve profile.
    ///
    /// The path is derived from the same profile directory as
    /// ``defaultSocketPath(profileID:fileManager:)``; this keeps diagnostics
    /// from reconstructing a second runtime-path convention.
    package static func defaultMetricsFileURL(
        profileID: String,
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) -> URL {
        URL(filePath: defaultSocketPath(profileID: profileID, fileManager: fileManager))
            .deletingLastPathComponent()
            .appending(path: "metrics.json")
    }

    /// Returns the live cache-events socket path for a stable serve profile.
    ///
    /// The path is derived from the same profile directory as
    /// ``defaultSocketPath(profileID:fileManager:)``; this keeps a tail
    /// client from reconstructing a second runtime-path convention.
    package static func defaultEventsSocketURL(
        profileID: String,
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) -> URL {
        URL(filePath: defaultSocketPath(profileID: profileID, fileManager: fileManager))
            .deletingLastPathComponent()
            .appending(path: XcodeCacheRuntimeDirectory.eventsSocketFileName)
    }

    /// Returns the detached server's process-record file for a stable serve profile.
    ///
    /// The path is derived from the same profile directory as
    /// ``defaultSocketPath(profileID:fileManager:)``; this keeps a stop
    /// command from reconstructing a second runtime-path convention.
    package static func defaultPIDFileURL(
        profileID: String,
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) -> URL {
        URL(filePath: defaultSocketPath(profileID: profileID, fileManager: fileManager))
            .deletingLastPathComponent()
            .appending(path: XcodeCacheRuntimeDirectory.pidFileName)
    }

    /// Returns the detached server's redirected stdout/stderr file for a stable serve profile.
    ///
    /// The path is derived from the same profile directory as
    /// ``defaultSocketPath(profileID:fileManager:)``; this keeps a detach
    /// launcher from reconstructing a second runtime-path convention.
    package static func defaultLogFileURL(
        profileID: String,
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) -> URL {
        URL(filePath: defaultSocketPath(profileID: profileID, fileManager: fileManager))
            .deletingLastPathComponent()
            .appending(path: XcodeCacheRuntimeDirectory.logFileName)
    }

    /// Reads and decodes a detached server's process record, if its pidfile exists and parses.
    ///
    /// The single decoding path a stop command and this runner's own startup
    /// checks would otherwise each reimplement.
    package static func readProcessRecord(
        at url: URL,
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) -> XcodeServeProcessRecord? {
        guard let data = fileManager.contents(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(XcodeServeProcessRecord.self, from: data)
    }

    /// Starts the server and returns once its socket endpoint is ready.
    ///
    /// A caller with a `processRecord` claims its pidfile lock first: the
    /// kernel releases that lock the instant a prior holder exits for any
    /// reason, so a claimable lock is itself proof the path is stale,
    /// without probing or interpreting the previous holder's PID. An existing
    /// socket is rejected only when something actually answers on it, since
    /// that alone can only mean a running server; otherwise it is unlinked as
    /// leftover from whichever process (if any) is confirmed gone by the lock
    /// having been claimable. The returned handle must be retained to keep
    /// the serving session under caller ownership.
    ///
    /// - Returns: A handle for observing or stopping the running server.
    /// - Throws: If the endpoint or its pidfile is held by a live process,
    ///   the runtime directory cannot be prepared, or the server fails
    ///   before readiness.
    package func start() async throws -> XcodeServeHandle {
        try XcodeCacheEnvironment.validate(workingDirectory: workingDirectory)
        let socketURL = URL(filePath: socketPath)
        let directory = socketURL.deletingLastPathComponent()
        let runtimeDirectory = XcodeCacheRuntimeDirectory(
            url: directory,
            fileManager: fileManager
        )
        try runtimeDirectory.create(withIntermediateDirectories: true)

        let pidFileLease = try claimPIDFileLease(runtimeDirectory: runtimeDirectory)
        do {
            try await prepareSocketPath()
        } catch {
            pidFileLease?.release()
            throw error
        }

        // `serverLifecycle.start` releases the lease itself on any failure
        // along its own path, since ownership only transfers to the session
        // it returns; a failure here must not release a lease the session
        // now owns.
        let session = try await serverLifecycle.start(
            runtimeDirectory: runtimeDirectory,
            casStore: casStore,
            actionCacheStore: actionCacheStore,
            serverFactory: serverFactory,
            metricsFileURL: runtimeDirectory.url.appending(path: "metrics.json"),
            pidFileLease: pidFileLease
        )
        let eventsOutcome = await X8CacheEventsListener(broadcaster: events)
            .start(at: runtimeDirectory.eventsSocketURL.path)
        return try XcodeServeHandle(
            session: session,
            events: events,
            workingDirectory: workingDirectory,
            eventsListenerOutcome: eventsOutcome,
            eventsSocketCleanup: { runtimeDirectory.removeEventsSocket() }
        )
    }

    /// Claims `processRecord`'s pidfile lock, or throws if it is already held.
    private func claimPIDFileLease(runtimeDirectory: XcodeCacheRuntimeDirectory) throws -> PIDFileLease? {
        guard let processRecord else { return nil }
        guard let lease = try PIDFileLease.claim(at: runtimeDirectory.pidFileURL, record: processRecord) else {
            throw XcodeCacheServerError.socketPathOccupied(socketPath: socketPath)
        }
        return lease
    }

    /// Reclaims a stale socket file, or rejects the path if it still looks live.
    ///
    /// A path already answering as a live listener is left untouched, since a
    /// listener that answers can only belong to a running process. Any other
    /// existing file is stale — a caller with a `processRecord` only reaches
    /// this point after confirming no prior holder's pidfile lock is still
    /// claimed, which is the only liveness signal that matters here.
    private func prepareSocketPath() async throws {
        guard fileManager.fileExists(atPath: socketPath) else { return }
        guard await !XcodeCacheSocketProbe.isListening(at: socketPath) else {
            throw XcodeCacheServerError.socketPathOccupied(socketPath: socketPath)
        }
        // The unlink itself failing (e.g. EPERM) must surface here rather than
        // fall through to a confusing bind failure against the file that remains.
        try fileManager.removeItem(atPath: socketPath)
    }
}
