import FileManagerProtocol
import Foundation
import X8Storage

/// Owns one short-lived Xcode cache proxy without running `xcodebuild`.
///
/// A session creates a private runtime directory, starts the cache server,
/// waits for its Unix socket, and exposes the environment contract needed by
/// an external Xcode client. Its shutdown drains the server and removes the
/// invocation-specific filesystem state. The caller owns the lifetime of the
/// external client and must pass `cacheEnvironment` to that client.
public final class XcodeCacheSession: Sendable {
    /// The Unix socket endpoint used by the cache proxy.
    public let socketPath: String

    /// The build settings an Xcode client must receive to use the proxy.
    ///
    /// Contains the three `COMPILATION_CACHE_*` settings and, unless the
    /// session was started with ``XcodeCachePrefixMapping/disabled``, six
    /// prefix-mapping settings and an empty module-validation session path.
    public let cacheEnvironment: [String: String]

    /// Why the events socket was not bound, when it wasn't.
    ///
    /// `nil` when no `eventsSocketURL` was supplied, or when the socket
    /// bound successfully. Set when binding was attempted and skipped, most
    /// often because another process already owns that socket for the same
    /// profile. The cache proxy is unaffected either way.
    public let eventsSocketWarning: String?

    private let serverSession: XcodeCacheServerSession
    private let runtimeDirectory: XcodeCacheRuntimeDirectory
    private let eventsTask: Task<Void, Never>?
    private let eventsSocketCleanup: @Sendable () -> Void

    /// Starts an invocation-scoped cache proxy.
    ///
    /// - Parameters:
    ///   - casStore: The provider-neutral CAS implementation served by the proxy.
    ///   - actionCacheStore: The provider-neutral Action Cache implementation.
    ///   - prefixMapping: Whether `cacheEnvironment` includes the prefix-mapping
    ///     settings. Defaults to `.enabled`; see ``XcodeCachePrefixMapping``.
    ///   - workingDirectory: The physical directory Xcode uses as the compiler
    ///     working directory. When supplied, it is mapped to `/^workspace`
    ///     in the client-facing cache settings.
    ///   - fileManager: The filesystem dependency used for runtime state.
    ///   - responseDirectory: Where disk-backed CAS response files are staged.
    ///     Pass the caller's resolved `-derivedDataPath` (or a directory known
    ///     to share its volume): Xcode's compilation-cache plugin links
    ///     response files into DerivedData, and a directory on a different
    ///     filesystem makes that link fail with `EXDEV`. `nil` stages response
    ///     files next to the session's own runtime directory.
    ///   - eventsSocketURL: When supplied, attempts to bind the live
    ///     cache-events socket at this path, so `x8 tail` can observe this
    ///     invocation's traffic. Callers that want the same socket
    ///     ``XcodeServeRunner`` uses should pass
    ///     `XcodeServeRunner.defaultEventsSocketURL(profileID:)`. The socket's
    ///     parent directory is created if missing. Binding is fail-open: a
    ///     concurrent `x8 serve` (or another invocation) already owning that
    ///     socket leaves this session's cache traffic unobserved by `tail`,
    ///     never unavailable — check ``eventsSocketWarning`` for the reason.
    ///     `nil` skips the events socket entirely.
    /// - Returns: A ready session whose socket can be passed to an external
    ///   Xcode client through `cacheEnvironment`.
    /// - Throws: If the runtime directory cannot be created or the cache server
    ///   cannot become ready.
    public static func start(
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        prefixMapping: XcodeCachePrefixMapping = .enabled,
        workingDirectory: URL? = nil,
        fileManager: any FileManagerProtocol = FileManager.default,
        responseDirectory: URL? = nil,
        eventsSocketURL: URL? = nil
    ) async throws -> XcodeCacheSession {
        let events = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore())
        return try await start(
            casStore: casStore,
            actionCacheStore: actionCacheStore,
            serverFactory: XcodeCacheServer.liveFactory(
                responseDirectory: responseDirectory,
                metrics: events
            ),
            prefixMapping: prefixMapping,
            workingDirectory: workingDirectory,
            fileManager: fileManager,
            events: events,
            eventsSocketURL: eventsSocketURL
        )
    }

    /// Gracefully stops the cache proxy and removes its invocation state.
    ///
    /// Calling this method more than once is safe. Shutdown errors from the
    /// serving task are intentionally treated as cleanup details by the
    /// underlying session.
    public func shutdown() async {
        await serverSession.shutdown()
        stopEventsSocket()
        runtimeDirectory.remove()
    }

    /// Starts a session with injectable server dependencies for package tests.
    package static func start(
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        serverFactory: @escaping XcodeCacheServerFactory,
        prefixMapping: XcodeCachePrefixMapping = .enabled,
        workingDirectory: URL? = nil,
        fileManager: any FileManagerProtocol = FileManager.default,
        serverLifecycle: XcodeCacheServerLifecycle? = nil,
        events: X8CacheEventBroadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore()),
        eventsSocketURL: URL? = nil
    ) async throws -> XcodeCacheSession {
        // Validate before creating any runtime state, so an unrepresentable
        // working directory fails fast without a server to clean up.
        try XcodeCacheEnvironment.validate(workingDirectory: workingDirectory)

        let runtimeDirectory = try makeRuntimeDirectory(fileManager: fileManager)
        do {
            let serverSession = try await (serverLifecycle ?? XcodeCacheServerLifecycle(
                fileManager: fileManager
            )).start(
                runtimeDirectory: runtimeDirectory,
                casStore: casStore,
                actionCacheStore: actionCacheStore,
                serverFactory: serverFactory
            )
            let eventsOutcome = await startEventsListener(
                at: eventsSocketURL,
                events: events,
                fileManager: fileManager
            )
            return try XcodeCacheSession(
                serverSession: serverSession,
                runtimeDirectory: runtimeDirectory,
                prefixMapping: prefixMapping,
                workingDirectory: workingDirectory,
                eventsListenerOutcome: eventsOutcome,
                eventsSocketURL: eventsSocketURL,
                fileManager: fileManager
            )
        } catch {
            runtimeDirectory.remove()
            throw error
        }
    }

    private init(
        serverSession: XcodeCacheServerSession,
        runtimeDirectory: XcodeCacheRuntimeDirectory,
        prefixMapping: XcodeCachePrefixMapping,
        workingDirectory: URL?,
        eventsListenerOutcome: X8CacheEventsListenerOutcome?,
        eventsSocketURL: URL?,
        fileManager: any FileManagerProtocol
    ) throws {
        self.serverSession = serverSession
        self.runtimeDirectory = runtimeDirectory
        socketPath = serverSession.socketPath
        cacheEnvironment = try XcodeCacheEnvironment.values(
            socketPath: socketPath,
            prefixMapping: prefixMapping,
            workingDirectory: workingDirectory
        )
        switch eventsListenerOutcome {
        case let .started(task):
            eventsTask = task
            eventsSocketWarning = nil
            eventsSocketCleanup = {
                guard let eventsSocketURL else { return }
                try? fileManager.removeItem(at: eventsSocketURL)
            }
        case let .skipped(reason):
            eventsTask = nil
            eventsSocketWarning = reason
            eventsSocketCleanup = {}
        case nil:
            eventsTask = nil
            eventsSocketWarning = nil
            eventsSocketCleanup = {}
        }
    }

    deinit {
        let serverSession = self.serverSession
        let runtimeDirectory = self.runtimeDirectory
        eventsTask?.cancel()
        let eventsSocketCleanup = self.eventsSocketCleanup
        Task {
            await serverSession.shutdown()
            eventsSocketCleanup()
            runtimeDirectory.remove()
        }
    }

    private func stopEventsSocket() {
        eventsTask?.cancel()
        eventsSocketCleanup()
    }

    private static func startEventsListener(
        at eventsSocketURL: URL?,
        events: X8CacheEventBroadcaster,
        fileManager: any FileManagerProtocol
    ) async -> X8CacheEventsListenerOutcome? {
        guard let eventsSocketURL else { return nil }
        // XcodeServeRunner always creates its profile directory before this
        // point; a caller reaching here on a machine where `x8 serve` has
        // never run for this profile would otherwise hit a bind ENOENT and
        // silently lose the events socket. Creation is fail-open like the
        // bind itself: a failure here still lets `start(at:)` attempt the
        // bind, which reports its own `.skipped` reason.
        try? XcodeCacheRuntimeDirectory(
            url: eventsSocketURL.deletingLastPathComponent(),
            fileManager: fileManager
        ).create(withIntermediateDirectories: true)
        return await X8CacheEventsListener(broadcaster: events).start(at: eventsSocketURL.path)
    }

    private static func makeRuntimeDirectory(
        fileManager: any FileManagerProtocol
    ) throws -> XcodeCacheRuntimeDirectory {
        let rootURL = URL(
            filePath: "/private/tmp/x8",
            directoryHint: .isDirectory
        )
        let rootDirectory = XcodeCacheRuntimeDirectory(
            url: rootURL,
            fileManager: fileManager
        )
        try rootDirectory.create(withIntermediateDirectories: true)

        let sessionURL = rootURL.appending(
            path: "x8-cache-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let runtimeDirectory = XcodeCacheRuntimeDirectory(
            url: sessionURL,
            fileManager: fileManager
        )
        try runtimeDirectory.create(withIntermediateDirectories: false)
        return runtimeDirectory
    }
}
