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

    private let serverSession: XcodeCacheServerSession
    private let runtimeDirectory: XcodeCacheRuntimeDirectory

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
        responseDirectory: URL? = nil
    ) async throws -> XcodeCacheSession {
        try await start(
            casStore: casStore,
            actionCacheStore: actionCacheStore,
            serverFactory: XcodeCacheServer.liveFactory(responseDirectory: responseDirectory),
            prefixMapping: prefixMapping,
            workingDirectory: workingDirectory,
            fileManager: fileManager
        )
    }

    /// Gracefully stops the cache proxy and removes its invocation state.
    ///
    /// Calling this method more than once is safe. Shutdown errors from the
    /// serving task are intentionally treated as cleanup details by the
    /// underlying session.
    public func shutdown() async {
        await serverSession.shutdown()
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
        serverLifecycle: XcodeCacheServerLifecycle? = nil
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
            return try XcodeCacheSession(
                serverSession: serverSession,
                runtimeDirectory: runtimeDirectory,
                prefixMapping: prefixMapping,
                workingDirectory: workingDirectory
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
        workingDirectory: URL?
    ) throws {
        self.serverSession = serverSession
        self.runtimeDirectory = runtimeDirectory
        socketPath = serverSession.socketPath
        cacheEnvironment = try XcodeCacheEnvironment.values(
            socketPath: socketPath,
            prefixMapping: prefixMapping,
            workingDirectory: workingDirectory
        )
    }

    deinit {
        let serverSession = self.serverSession
        let runtimeDirectory = self.runtimeDirectory
        Task {
            await serverSession.shutdown()
            runtimeDirectory.remove()
        }
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
