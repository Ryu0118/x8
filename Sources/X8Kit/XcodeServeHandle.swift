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
package final class XcodeServeHandle: Sendable {
    /// The Unix socket path exposed to Xcode.
    package let socketPath: String

    /// The build settings needed by an Xcode client using this server.
    ///
    /// Contains the three `COMPILATION_CACHE_*` settings, six prefix-mapping
    /// settings (``XcodeCachePrefixMapping``), an empty module-validation
    /// session path, and the optional working-directory mapping selected by
    /// the runner. Computed once at handle creation, since the runner that
    /// constructs a handle has already validated its working directory.
    package let cacheEnvironment: [String: String]

    /// Explains why the live cache-events socket did not start, if it did not.
    ///
    /// `nil` means the socket is serving connections, or that a caller
    /// disabled it entirely. The events socket is a diagnostic convenience:
    /// its absence never affects cache serving.
    package let eventsSocketWarning: String?

    private let session: XcodeCacheServerSession
    private let makeTerminationSignalWaiter: @Sendable () -> any TerminationSignalWaiting
    private let eventsTask: Task<Void, Never>?
    private let eventsSocketCleanup: @Sendable () -> Void
    private let events: X8CacheEventBroadcaster

    /// Waits until the server stops or its transport fails.
    ///
    /// The owned socket is cleaned up when the serving task completes. A
    /// transport failure is rethrown after that cleanup.
    package func wait() async throws {
        do {
            try await session.wait()
        } catch {
            stopEventsSocket()
            throw error
        }
        stopEventsSocket()
    }

    /// Requests graceful shutdown and waits for active requests to drain.
    ///
    /// The method is non-throwing because it is a cleanup operation; serving
    /// task failures are observed internally while the endpoint is removed.
    package func shutdown() async {
        await session.shutdown()
        stopEventsSocket()
    }

    /// Subscribes to this server's live cache events in-process.
    ///
    /// Unlike the events socket that ``x8 tail`` dials, this delivers events
    /// directly from the broadcaster the server already records through, so
    /// it works whether or not the events socket started.
    ///
    /// - Parameter bufferLimit: The number of most-recent events retained for
    ///   a subscriber that is not keeping up; older events are dropped first.
    package func subscribeToEvents(bufferLimit: Int = 64) async -> AsyncStream<X8CacheMetricsEvent> {
        await events.subscribe(bufferLimit: bufferLimit)
    }

    /// Waits for a termination signal or server failure, then shuts down gracefully.
    ///
    /// A `SIGINT` or `SIGTERM` results in normal completion after draining. A
    /// server failure is rethrown after shutdown. Cancellation of the waiting
    /// task also follows the shutdown path and is propagated to the caller.
    package func waitForTerminationSignal() async throws {
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
    /// - Parameter eventsListenerOutcome: The result of attempting to start
    ///   the live cache-events socket, or `nil` when a caller never attempts
    ///   one.
    package init(
        session: XcodeCacheServerSession,
        events: X8CacheEventBroadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore()),
        workingDirectory: URL? = nil,
        makeTerminationSignalWaiter: @escaping @Sendable () -> any TerminationSignalWaiting = {
            TerminationSignalWaiter()
        },
        eventsListenerOutcome: X8CacheEventsListenerOutcome? = nil,
        eventsSocketCleanup: @escaping @Sendable () -> Void = {}
    ) throws {
        self.session = session
        self.events = events
        self.makeTerminationSignalWaiter = makeTerminationSignalWaiter
        self.eventsSocketCleanup = eventsSocketCleanup
        socketPath = session.socketPath
        cacheEnvironment = try XcodeCacheEnvironment.values(
            socketPath: socketPath,
            prefixMapping: .enabled,
            workingDirectory: workingDirectory
        )
        switch eventsListenerOutcome {
        case let .started(task):
            eventsTask = task
            eventsSocketWarning = nil
        case let .skipped(reason):
            eventsTask = nil
            eventsSocketWarning = reason
        case nil:
            eventsTask = nil
            eventsSocketWarning = nil
        }
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

    private func stopEventsSocket() {
        eventsTask?.cancel()
        eventsSocketCleanup()
    }
}

private enum ServerWaitEvent: Sendable {
    case server
    case termination
}
