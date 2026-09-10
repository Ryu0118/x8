import FileManagerProtocol
import Foundation
import X8Storage

/// Coordinates the startup and teardown boundary for one Xcode cache server.
///
/// The coordinator constructs a server, starts its long-running `serve()` task,
/// and waits until the server's Unix socket exists before returning. Readiness
/// is therefore an operating-system endpoint guarantee, not merely a task
/// creation guarantee. A successful call transfers the running task and socket
/// cleanup responsibility to `XcodeCacheServerSession`.
///
/// If the server exits early, readiness times out, the socket setup fails, or
/// the caller is cancelled, the coordinator requests graceful shutdown,
/// awaits the serving task, removes the socket, and rethrows the original
/// failure.
package struct XcodeCacheServerLifecycle: Sendable {
    private let startupTimeout: Duration
    private let startupPollInterval: Duration
    private let fileManager: any FileManagerProtocol

    /// Creates a lifecycle coordinator with deterministic readiness policy.
    ///
    /// The defaults bound startup waiting for live runners. Tests may inject
    /// shorter intervals and the same filesystem dependency used by the
    /// runner without changing server behavior.
    package init(
        startupTimeout: Duration = .seconds(5),
        startupPollInterval: Duration = .milliseconds(10),
        fileManager: any FileManagerProtocol = FileManager.default
    ) {
        self.startupTimeout = startupTimeout
        self.startupPollInterval = startupPollInterval
        self.fileManager = fileManager
    }

    /// Starts a server and returns only after its Unix socket is ready.
    ///
    /// The factory is called before `serve()` starts, so the returned server is
    /// configured but not independently started. This method owns the serving
    /// task while readiness is being established and hands that ownership to
    /// the returned session only after the socket permissions are configured.
    /// A server that cannot reach readiness is never returned to the caller.
    ///
    /// - Parameters:
    ///   - runtimeDirectory: The prepared directory containing the Unix socket endpoint.
    ///   - casStore: The provider-neutral CAS implementation served by the server.
    ///   - actionCacheStore: The provider-neutral Action Cache implementation.
    ///   - serverFactory: The factory that creates the configured server.
    /// - Returns: A session that owns the ready server task and socket cleanup.
    /// - Throws: A startup, filesystem, cancellation, or server error. Any
    ///   server started before the error is drained and cleaned up first.
    package func start(
        runtimeDirectory: XcodeCacheRuntimeDirectory,
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        serverFactory: @escaping XcodeCacheServerFactory,
        metricsFileURL: URL? = nil
    ) async throws -> XcodeCacheServerSession {
        let socketPath = runtimeDirectory.socketURL.path
        let server = serverFactory(socketPath, casStore, actionCacheStore, fileManager)
        let startupState = ServerStartupState()
        let task = Task {
            do {
                try await server.serve()
            } catch {
                await startupState.markFinished()
                throw error
            }
            await startupState.markFinished()
        }

        do {
            // Keep task ownership here until the socket is ready; only a returned session may outlive startup.
            try await waitForSocket(
                at: socketPath,
                state: startupState
            )
            try runtimeDirectory.protectSocket()
            return XcodeCacheServerSession(
                server: server,
                task: task,
                runtimeDirectory: runtimeDirectory,
                metricsFileURL: metricsFileURL,
                fileManager: fileManager
            )
        } catch {
            // Startup still owns the task, so drain it before removing the endpoint and rethrowing the original error.
            server.beginGracefulShutdown()
            _ = await task.result
            runtimeDirectory.removeSocket()
            throw error
        }
    }

    /// Starts a server using a listener descriptor supplied by launchd.
    ///
    /// The descriptor is already bound and ready, so this path never polls for
    /// or changes the socket node. The returned session deliberately does not
    /// own endpoint cleanup; launchd owns the socket lifecycle.
    package func startActivated(
        runtimeDirectory: XcodeCacheRuntimeDirectory,
        listeningSocketDescriptor: Int,
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        serverFactory: @escaping XcodeCacheActivatedServerFactory,
        metricsFileURL: URL? = nil
    ) async throws -> XcodeCacheServerSession {
        let server = serverFactory(
            runtimeDirectory.socketURL.path,
            listeningSocketDescriptor,
            casStore,
            actionCacheStore,
            fileManager
        )
        let task = Task {
            try await server.serve()
        }
        return XcodeCacheServerSession(
            server: server,
            task: task,
            ownsSocket: false,
            runtimeDirectory: runtimeDirectory,
            metricsFileURL: metricsFileURL,
            fileManager: fileManager
        )
    }

    private func waitForSocket(
        at path: String,
        state: ServerStartupState
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: startupTimeout)
        // A missing socket can mean either that startup is pending or that the server already failed.
        // Polling the shared state with the endpoint distinguishes those cases without waiting for the timeout.
        while clock.now < deadline,
              try await shouldContinueWaiting(
                  at: path,
                  state: state
              )
        {
            try Task.checkCancellation()
            try await Task.sleep(for: startupPollInterval)
        }
        guard fileManager.fileExists(atPath: path) else {
            throw XcodeCacheServerError.startupTimedOut(socketPath: path)
        }
    }

    private func shouldContinueWaiting(
        at path: String,
        state: ServerStartupState
    ) async throws -> Bool {
        guard await !(state.didFinish) else {
            throw XcodeCacheServerError.stoppedBeforeReady(socketPath: path)
        }
        return !fileManager.fileExists(atPath: path)
    }
}

private actor ServerStartupState {
    private(set) var didFinish = false

    func markFinished() {
        didFinish = true
    }
}
