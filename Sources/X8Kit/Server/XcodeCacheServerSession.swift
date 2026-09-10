import FileManagerProtocol
import Foundation

/// Owns one ready cache server, its serving task, and endpoint cleanup.
///
/// A session is created only after `XcodeCacheServerLifecycle` observes the
/// server's Unix socket. Retaining the session keeps the serving task alive.
/// `wait()` observes the server's natural completion, while `shutdown()` asks
/// it to drain and waits for completion. Both remove the socket when this
/// session owns it; `beginGracefulShutdown()` only sends the request and does
/// not wait.
///
/// Dropping a session also requests graceful shutdown. Its deinitializer cannot
/// await the task, so it launches a short-lived cleanup task that waits for the
/// server before removing an owned socket.
package final class XcodeCacheServerSession: Sendable {
    /// The Unix socket path exposed by the server.
    package let socketPath: String

    private let server: any XcodeCacheServing
    private let task: Task<Void, Error>
    private let runtimeDirectory: XcodeCacheRuntimeDirectory
    private let metricsFileURL: URL?
    private let metricsFile: X8CacheMetricsSnapshotFile
    /// A supervisor such as launchd can retain ownership of the socket node.
    private let ownsSocket: Bool

    /// Creates a session from a ready server and its serving task.
    ///
    /// - Parameters:
    ///   - server: The server whose `serve()` task is already running and ready.
    ///   - task: The task that owns the server's long-running serving operation.
    ///   - ownsSocket: Whether this session is responsible for removing the
    ///     socket after the task stops. Set this to `false` when an external
    ///     supervisor owns the endpoint node.
    ///   - runtimeDirectory: The runtime directory that contains the server socket.
    ///   - fileManager: The filesystem dependency used to create a fallback
    ///     runtime-directory value when `runtimeDirectory` is omitted.
    package init(
        server: any XcodeCacheServing,
        task: Task<Void, Error>,
        ownsSocket: Bool = true,
        runtimeDirectory: XcodeCacheRuntimeDirectory? = nil,
        metricsFileURL: URL? = nil,
        fileManager: any FileManagerProtocol = FileManager.default
    ) {
        socketPath = server.socketPath
        self.server = server
        self.task = task
        self.ownsSocket = ownsSocket
        self.metricsFileURL = metricsFileURL
        metricsFile = X8CacheMetricsSnapshotFile(fileManager: fileManager)
        self.runtimeDirectory = runtimeDirectory ?? XcodeCacheRuntimeDirectory(
            url: URL(filePath: server.socketPath).deletingLastPathComponent(),
            fileManager: fileManager
        )
    }

    /// Waits for the server to stop and then removes its owned socket.
    ///
    /// A serving error is rethrown after cleanup, so callers can distinguish a
    /// normal shutdown from a transport failure.
    package func wait() async throws {
        do {
            try await task.value
        } catch {
            await persistMetrics()
            removeSocket()
            throw error
        }
        await persistMetrics()
        removeSocket()
    }

    /// Requests graceful shutdown, waits for the task, and cleans up the socket.
    ///
    /// This method is intentionally non-throwing: shutdown is a cleanup path,
    /// so any serving-task error is observed and discarded after the endpoint
    /// has been drained.
    package func shutdown() async {
        server.beginGracefulShutdown()
        _ = await task.result
        await persistMetrics()
        removeSocket()
    }

    /// Signals graceful shutdown without waiting for completion.
    ///
    /// Retain the session and call `wait()` or `shutdown()` when the caller
    /// needs to observe completion and endpoint cleanup.
    package func beginGracefulShutdown() {
        server.beginGracefulShutdown()
    }

    deinit {
        let server = server
        let task = task
        let ownsSocket = ownsSocket
        let runtimeDirectory = runtimeDirectory
        let metricsFileURL = metricsFileURL
        let metricsFile = metricsFile
        let metrics = server.metrics

        // A dropped handle cannot await shutdown. Keep the session alive until the server drains.
        server.beginGracefulShutdown()
        Task {
            _ = await task.result
            if let metrics, let metricsFileURL {
                let snapshot = await metrics.snapshot()
                // Diagnostic persistence must not keep a dropped handle alive or surface from deinit.
                try? await metricsFile.write(snapshot, to: metricsFileURL)
            }
            guard ownsSocket else { return }
            runtimeDirectory.removeSocket()
        }
    }

    private func persistMetrics() async {
        guard let metrics = server.metrics, let metricsFileURL else { return }
        let snapshot = await metrics.snapshot()
        // Shutdown should preserve the transport result even if a diagnostic file cannot be written.
        try? await metricsFile.write(snapshot, to: metricsFileURL)
    }

    private func removeSocket() {
        guard ownsSocket else { return }
        runtimeDirectory.removeSocket()
    }
}
