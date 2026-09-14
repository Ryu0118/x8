import Foundation
import NIOCore
import NIOPosix
import Testing
@testable import X8Kit
import X8Storage

@Suite("Xcode standalone server stale-socket reclamation")
struct XcodeServeRunnerIntegrationTests {
    @Test("refuses a path a live listener answers on, even with an unheld pidfile")
    func refusesLiveListenerRegardlessOfPIDFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let server = try await ServerBootstrap(group: .singletonMultiThreadedEventLoopGroup)
            .bind(unixDomainSocketPath: socket.path) { channel in
                channel.eventLoop.makeSucceededFuture(channel)
            }
        let listenerTask = Task {
            try? await server.executeThenClose { connections in
                for try await _ in connections {}
            }
        }
        defer { listenerTask.cancel() }

        // A leftover, unheld pidfile from an unrelated prior process. The
        // listening probe alone must still refuse this path.
        let record = XcodeServeProcessRecord(pid: 1, startTime: 0, executablePath: "/usr/bin/x8")
        try JSONEncoder().encode(record).write(to: directory.appending(path: "serve.pid"))

        let storage = InMemoryStorage()
        let runner = XcodeServeRunner(
            socketPath: socket.path,
            casStore: storage,
            actionCacheStore: storage
        )

        do {
            _ = try await runner.start()
            Issue.record("Expected the live listener's path to be rejected.")
        } catch let error as XcodeCacheServerError {
            #expect(error == .socketPathOccupied(socketPath: socket.path))
        } catch {
            Issue.record("Expected a socket-path error, got \(error).")
        }
    }
}
