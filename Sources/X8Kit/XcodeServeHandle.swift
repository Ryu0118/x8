import AsyncOperations
import Foundation

/// Owns and controls one ready standalone Xcode cache server.
///
/// The handle is returned only after the server's Unix socket exists. Retain
/// it for as long as clients need the endpoint. `wait()` observes natural
/// server completion and propagates transport failures; `shutdown()` requests
/// a graceful drain and waits for cleanup. `waitForTerminationSignal()` is a
/// convenience for a foreground process or supervisor that should translate
/// `SIGINT`/`SIGTERM` into the same graceful shutdown path.
public final class XcodeServeHandle: Sendable {
    /// The Unix socket path exposed to Xcode.
    public let socketPath: String

    /// The build settings needed by an Xcode client using this server.
    ///
    /// Contains the three `COMPILATION_CACHE_*` settings, six prefix-mapping
    /// settings (``XcodeCachePrefixMapping``), an empty module-validation
    /// session path, and the optional working-directory mapping selected by
    /// the runner. Computed once at handle creation, since the runner that
    /// constructs a handle has already validated its working directory.
    public let cacheEnvironment: [String: String]

    private let session: XcodeCacheServerSession
    private let makeTerminationSignalWaiter: @Sendable () -> any TerminationSignalWaiting

    /// Waits until the server stops or its transport fails.
    ///
    /// The owned socket is cleaned up when the serving task completes. A
    /// transport failure is rethrown after that cleanup.
    public func wait() async throws {
        try await session.wait()
    }

    /// Requests graceful shutdown and waits for active requests to drain.
    ///
    /// The method is non-throwing because it is a cleanup operation; serving
    /// task failures are observed internally while the endpoint is removed.
    public func shutdown() async {
        await session.shutdown()
    }

    /// Waits for a termination signal or server failure, then shuts down gracefully.
    ///
    /// A `SIGINT` or `SIGTERM` results in normal completion after draining. A
    /// server failure is rethrown after shutdown. Cancellation of the waiting
    /// task also follows the shutdown path and is propagated to the caller.
    public func waitForTerminationSignal() async throws {
        let waiter = makeTerminationSignalWaiter()
        do {
            try await waitForServerOrTermination(using: waiter)
        } catch {
            await shutdown()
            throw error
        }
        await shutdown()
        try Task.checkCancellation()
    }

    /// Creates a handle for an already-started server session.
    ///
    /// - Precondition: The caller has already validated `workingDirectory`
    ///   with ``XcodeCacheEnvironment/validate(workingDirectory:)`` before
    ///   starting the server this handle wraps, since an unrepresentable
    ///   working directory should fail before any server-side resource is
    ///   created.
    package init(
        session: XcodeCacheServerSession,
        workingDirectory: URL? = nil,
        makeTerminationSignalWaiter: @escaping @Sendable () -> any TerminationSignalWaiting = {
            TerminationSignalWaiter()
        }
    ) throws {
        self.session = session
        self.makeTerminationSignalWaiter = makeTerminationSignalWaiter
        socketPath = session.socketPath
        cacheEnvironment = try XcodeCacheEnvironment.values(
            socketPath: socketPath,
            prefixMapping: .enabled,
            workingDirectory: workingDirectory
        )
    }

    private func waitForServerOrTermination(
        using waiter: any TerminationSignalWaiting
    ) async throws {
        let events: [ServerWaitEvent] = [.server, .termination]
        _ = try await events.asyncContains(numberOfConcurrentTasks: 2) { event in
            switch event {
            case .server:
                try await self.session.wait()
            case .termination:
                _ = await waiter.wait()
                self.session.beginGracefulShutdown()
            }
            return true
        }
    }
}

private enum ServerWaitEvent: Sendable {
    case server
    case termination
}
