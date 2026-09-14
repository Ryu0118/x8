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
    public init(
        socketPath: String,
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        workingDirectory: URL? = nil,
        fileManager: any FileManagerProtocolMacOS = FileManager.default,
        metrics: any X8CacheMetricsRecorder = X8CacheMetricsStore()
    ) {
        let events = X8CacheEventBroadcaster(wrapping: metrics)
        self.init(
            socketPath: socketPath,
            casStore: casStore,
            actionCacheStore: actionCacheStore,
            serverFactory: XcodeCacheServer.liveFactory(metrics: events),
            workingDirectory: workingDirectory,
            fileManager: fileManager,
            events: events
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
        events: X8CacheEventBroadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore())
    ) {
        self.socketPath = socketPath
        self.casStore = casStore
        self.actionCacheStore = actionCacheStore
        self.serverFactory = serverFactory
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        self.events = events
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
    /// An existing path is rejected rather than unlinked because it may belong
    /// to another live server or an external supervisor. The returned handle
    /// must be retained to keep the serving session under caller ownership.
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
        try prepareSocketPath()
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
            workingDirectory: workingDirectory,
            eventsListenerOutcome: eventsOutcome,
            eventsSocketCleanup: { runtimeDirectory.removeEventsSocket() }
        )
    }

    private func prepareSocketPath() throws {
        guard fileManager.fileExists(atPath: socketPath) else { return }
        // Never unlink an existing endpoint: it may belong to a live server or an external supervisor.
        throw XcodeCacheServerError.socketPathOccupied(socketPath: socketPath)
    }
}
