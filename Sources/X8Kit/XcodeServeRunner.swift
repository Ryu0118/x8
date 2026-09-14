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
public struct XcodeServeRunner: Sendable {
    private let socketPath: String
    private let casStore: any CASStore
    private let actionCacheStore: any ActionCacheStore
    private let serverFactory: XcodeCacheServerFactory
    private let serverLifecycle: XcodeCacheServerLifecycle
    private let fileManager: any FileManagerProtocolMacOS
    private let workingDirectory: URL?
    private let events: X8CacheEventBroadcaster
    private let livenessProbe: any ProcessLivenessProbing

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
    ///   - livenessProbe: Determines whether a PID recorded in a stale-looking
    ///     socket's pidfile is still running. Defaults to treating every
    ///     recorded process as alive, so a caller without a liveness check
    ///     never reclaims a socket whose pidfile it cannot disprove — a
    ///     socket with no pidfile at all is still reclaimed once nothing
    ///     answers on it. A frontend that can check process liveness should
    ///     inject its live implementation here.
    public init(
        socketPath: String,
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        workingDirectory: URL? = nil,
        fileManager: any FileManagerProtocolMacOS = FileManager.default,
        metrics: any X8CacheMetricsRecorder = X8CacheMetricsStore(),
        livenessProbe: any ProcessLivenessProbing = AlwaysAliveProcessLivenessProbe()
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
            livenessProbe: livenessProbe
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
        livenessProbe: any ProcessLivenessProbing = AlwaysAliveProcessLivenessProbe()
    ) {
        self.socketPath = socketPath
        self.casStore = casStore
        self.actionCacheStore = actionCacheStore
        self.serverFactory = serverFactory
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        self.events = events
        self.livenessProbe = livenessProbe
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
    public static func defaultSocketPath(
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
    public static func defaultMetricsFileURL(
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
    public static func defaultEventsSocketURL(
        profileID: String,
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) -> URL {
        URL(filePath: defaultSocketPath(profileID: profileID, fileManager: fileManager))
            .deletingLastPathComponent()
            .appending(path: XcodeCacheRuntimeDirectory.eventsSocketFileName)
    }

    /// Starts the server and returns once its socket endpoint is ready.
    ///
    /// An existing path is rejected when it still looks live — answering a
    /// connection, or naming a pidfile whose process the injected
    /// ``ProcessLivenessProbing`` confirms alive — since it may belong to
    /// another running server. A path with no answering listener and no
    /// confirmed-live pidfile is stale and reclaimed automatically. The
    /// returned handle must be retained to keep the serving session under
    /// caller ownership.
    ///
    /// - Returns: A handle for observing or stopping the running server.
    /// - Throws: If the endpoint is occupied, its directory cannot be prepared,
    ///   or the server fails before readiness.
    public func start() async throws -> XcodeServeHandle {
        try XcodeCacheEnvironment.validate(workingDirectory: workingDirectory)
        let socketURL = URL(filePath: socketPath)
        let directory = socketURL.deletingLastPathComponent()
        let runtimeDirectory = XcodeCacheRuntimeDirectory(
            url: directory,
            fileManager: fileManager
        )
        try runtimeDirectory.create(withIntermediateDirectories: true)
        try await prepareSocketPath(runtimeDirectory: runtimeDirectory)
        let session = try await serverLifecycle.start(
            runtimeDirectory: runtimeDirectory,
            casStore: casStore,
            actionCacheStore: actionCacheStore,
            serverFactory: serverFactory,
            metricsFileURL: runtimeDirectory.url.appending(path: "metrics.json")
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

    /// Reclaims a stale socket file, or rejects the path if it still looks live.
    ///
    /// A path already answering as a live listener is left untouched — the
    /// connection probe alone settles that, regardless of a pidfile's
    /// content or absence, since a listener that answers can only belong to a
    /// running process. Only when nothing answers does the pidfile matter: an
    /// absent, unreadable, or dead-process pidfile marks the socket stale and
    /// safe to unlink, while a pidfile whose process is confirmed alive
    /// still refuses the path.
    private func prepareSocketPath(runtimeDirectory: XcodeCacheRuntimeDirectory) async throws {
        guard fileManager.fileExists(atPath: socketPath) else { return }
        guard await !XcodeCacheSocketProbe.isListening(at: socketPath) else {
            throw XcodeCacheServerError.socketPathOccupied(socketPath: socketPath)
        }
        if let record = readProcessRecord(at: runtimeDirectory.pidFileURL), livenessProbe.isAlive(record) {
            throw XcodeCacheServerError.socketPathOccupied(socketPath: socketPath)
        }
        // The unlink itself failing (e.g. EPERM) must surface here rather than
        // fall through to a confusing bind failure against the file that remains.
        try fileManager.removeItem(atPath: socketPath)
        runtimeDirectory.removePIDFile()
    }

    private func readProcessRecord(at url: URL) -> XcodeServeProcessRecord? {
        guard let data = fileManager.contents(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(XcodeServeProcessRecord.self, from: data)
    }
}
