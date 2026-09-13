import Foundation
import Testing
@testable import X8Kit
import X8Storage

@Suite("Xcode cache session binds its events socket")
struct XcodeCacheSessionEventsSocketIntegrationTests {
    @Test("creates a missing parent directory and binds, then removes the socket on shutdown")
    func createsMissingDirectoryAndCleansUpOnShutdown() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventsSocketURL = directory.appending(path: "events.sock")

        let storage = InMemoryStorage()
        let session = try await XcodeCacheSession.start(
            casStore: storage,
            actionCacheStore: storage,
            eventsSocketURL: eventsSocketURL
        )

        #expect(session.eventsSocketWarning == nil)
        #expect(FileManager.default.fileExists(atPath: eventsSocketURL.path))

        await session.shutdown()

        #expect(FileManager.default.fileExists(atPath: eventsSocketURL.path) == false)
    }

    @Test("reports a warning instead of failing when another listener already owns the path")
    func reportsWarningWhenPathIsAlreadyOwned() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let eventsSocketURL = directory.appending(path: "events.sock")

        let broadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore())
        guard case let .started(listenerTask) = await X8CacheEventsListener(broadcaster: broadcaster)
            .start(at: eventsSocketURL.path)
        else {
            Issue.record("Expected the first listener to start.")
            return
        }
        defer { listenerTask.cancel() }

        let storage = InMemoryStorage()
        let session = try await XcodeCacheSession.start(
            casStore: storage,
            actionCacheStore: storage,
            eventsSocketURL: eventsSocketURL
        )

        #expect(session.eventsSocketWarning?.contains("another listener") == true)

        await session.shutdown()
    }

    private func temporaryDirectory() -> URL {
        // A short, fixed-depth path: /var/folders/.../x8-session-events-<UUID>/
        // plus "events.sock" can exceed the ~104-byte Unix domain socket path
        // limit, failing the bind with unixDomainSocketPathTooLong before the
        // behavior under test ever runs.
        URL(filePath: "/private/tmp", directoryHint: .isDirectory)
            .appending(path: "x8-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    }
}
