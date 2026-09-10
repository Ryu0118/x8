import Foundation
@testable import X8Kit

/// A deterministic server double that models socket readiness and graceful drain.
final class TestCacheServer: XcodeCacheServing, @unchecked Sendable {
    let socketPath: String

    private let shutdown: AsyncStream<Void>
    private let shutdownContinuation: AsyncStream<Void>.Continuation
    private let stopped: AsyncStream<Void>
    private let stoppedContinuation: AsyncStream<Void>.Continuation

    init(socketPath: String) {
        self.socketPath = socketPath
        (shutdown, shutdownContinuation) = AsyncStream.makeStream(of: Void.self)
        (stopped, stoppedContinuation) = AsyncStream.makeStream(of: Void.self)
        FileManager.default.createFile(atPath: socketPath, contents: nil)
    }

    func serve() async throws {
        for await _ in shutdown {}
        stoppedContinuation.finish()
    }

    func beginGracefulShutdown() {
        shutdownContinuation.finish()
    }

    func waitUntilStopped() async {
        for await _ in stopped {}
    }
}
