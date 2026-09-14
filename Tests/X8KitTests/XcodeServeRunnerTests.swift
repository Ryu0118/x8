import Darwin
import Foundation
import Testing
@testable import X8Kit
import X8Storage

@Suite("Xcode standalone server socket ownership")
struct XcodeServeRunnerTests {
    @Test
    func reclaimsStaleSocketWithNoPIDFile() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            FileManager.default.createFile(atPath: socket.path, contents: nil)

            let storage = InMemoryStorage()
            let runner = XcodeServeRunner(
                socketPath: socket.path,
                casStore: storage,
                actionCacheStore: storage,
                serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) }
            )

            let handle = try await runner.start()
            #expect(handle.socketPath == socket.path)
            await handle.shutdown()
        }
    }

    @Test
    func concreteServerExposesMetricsThroughProtocol() {
        let storage = InMemoryStorage()
        let server: any XcodeCacheServing = XcodeCacheServer(
            socketPath: "/tmp/x8-witness-\(UUID().uuidString).sock",
            casStore: storage,
            actionCacheStore: storage
        )
        #expect(server.metrics != nil)
    }

    @Test
    func defaultSocketPathIsStableForOneProfile() {
        let first = XcodeServeRunner.defaultSocketPath(profileID: "foo")
        let second = XcodeServeRunner.defaultSocketPath(profileID: "foo")
        let other = XcodeServeRunner.defaultSocketPath(profileID: "bar")

        #expect(first == second)
        #expect(first != other)
        #expect(first.hasSuffix("/X8/foo/cache.sock"))
    }

    @Test
    func startsAnInjectedServerAndCleansUpOnShutdown() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            let storage = InMemoryStorage()
            let workingDirectory = URL(filePath: "/worktrees/MyApp")
            let runner = XcodeServeRunner(
                socketPath: socket.path,
                casStore: storage,
                actionCacheStore: storage,
                serverFactory: { socketPath, _, _, _ in
                    TestCacheServer(socketPath: socketPath)
                },
                workingDirectory: workingDirectory
            )

            let handle = try await runner.start()
            #expect(handle.socketPath == socket.path)
            #expect(
                handle.cacheEnvironment["SWIFT_OTHER_PREFIX_MAPPINGS"]?.contains(
                    "/worktrees/MyApp=/^workspace"
                ) == true
            )
            #expect(FileManager.default.fileExists(atPath: socket.path))

            await handle.shutdown()

            #expect(FileManager.default.fileExists(atPath: socket.path) == false)
        }
    }

    @Test
    func terminationSignalWaitUsesInjectedWaiterAndShutsDown() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            let server = TestCacheServer(socketPath: socket.path)
            let task = Task { try await server.serve() }
            let session = XcodeCacheServerSession(server: server, task: task)
            let handle = try XcodeServeHandle(
                session: session,
                makeTerminationSignalWaiter: { ImmediateTerminationSignalWaiter() }
            )

            try await handle.waitForTerminationSignal()

            #expect(FileManager.default.fileExists(atPath: socket.path) == false)
        }
    }

    @Test
    func cancellationWaitsForShutdownThenPropagates() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            let server = TestCacheServer(socketPath: socket.path)
            let task = Task { try await server.serve() }
            let session = XcodeCacheServerSession(server: server, task: task)
            let handle = try XcodeServeHandle(
                session: session,
                makeTerminationSignalWaiter: { NeverTerminationSignalWaiter() }
            )
            let waitTask = Task { try await handle.waitForTerminationSignal() }

            waitTask.cancel()

            await #expect(throws: CancellationError.self) {
                try await waitTask.value
            }
            #expect(FileManager.default.fileExists(atPath: socket.path) == false)
        }
    }

    @Test
    func serverFailureStillTriggersGracefulCleanup() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            FileManager.default.createFile(atPath: socket.path, contents: nil)

            let server = FailingRunningServer(socketPath: socket.path)
            let task = Task { try await server.serve() }
            let session = XcodeCacheServerSession(server: server, task: task)
            let handle = try XcodeServeHandle(
                session: session,
                makeTerminationSignalWaiter: { NeverTerminationSignalWaiter() }
            )

            await #expect(throws: ServerFailure.self) {
                try await handle.waitForTerminationSignal()
            }
            #expect(FileManager.default.fileExists(atPath: socket.path) == false)
        }
    }

    @Test
    func droppedHandleCleansUpAfterServerStops() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            let server = TestCacheServer(socketPath: socket.path)
            let task = Task { try await server.serve() }
            var handle: XcodeServeHandle? = try XcodeServeHandle(
                session: XcodeCacheServerSession(server: server, task: task)
            )
            #expect(handle != nil)
            #expect(FileManager.default.fileExists(atPath: socket.path))

            handle = nil
            await server.waitUntilStopped()

            // Session cleanup runs after the serving task completes.
            for _ in 0 ..< 100 where FileManager.default.fileExists(atPath: socket.path) {
                await Task.yield()
            }
            #expect(FileManager.default.fileExists(atPath: socket.path) == false)
        }
    }

    @Test
    func claimsPIDFileForDetachedProcessOnStart() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            let storage = InMemoryStorage()
            let record = XcodeServeProcessRecord(pid: 42, startTime: 100, executablePath: "/usr/bin/x8")
            let runner = XcodeServeRunner(
                socketPath: socket.path,
                casStore: storage,
                actionCacheStore: storage,
                serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) },
                processRecord: record
            )

            let handle = try await runner.start()
            let pidFile = directory.appending(path: "serve.pid")
            let decoded = XcodeServeRunner.readProcessRecord(at: pidFile)
            #expect(decoded == record)

            await handle.shutdown()
        }
    }

    @Test
    func refusesToClaimPIDFileWhenLockIsAlreadyHeld() async throws {
        try await withTempDirectory { directory in
            let pidFile = directory.appending(path: "serve.pid")
            let holder = try #require(lockPIDFile(at: pidFile))
            defer { close(holder) }

            let storage = InMemoryStorage()
            let record = XcodeServeProcessRecord(pid: 42, startTime: 100, executablePath: "/usr/bin/x8")
            let runner = XcodeServeRunner(
                socketPath: directory.appending(path: "cache.sock").path,
                casStore: storage,
                actionCacheStore: storage,
                serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) },
                processRecord: record
            )

            do {
                _ = try await runner.start()
                Issue.record("Expected a held pidfile lock to refuse the claim.")
            } catch let error as XcodeCacheServerError {
                #expect(error == .socketPathOccupied(socketPath: directory.appending(path: "cache.sock").path))
            } catch {
                Issue.record("Expected a socket-path error, got \(error).")
            }
        }
    }

    @Test
    func reclaimsPIDFileLeftBehindByADeadProcess() async throws {
        try await withTempDirectory { directory in
            let pidFile = directory.appending(path: "serve.pid")
            // Simulate a crashed prior holder: a pidfile exists but nothing holds its lock.
            let staleRecord = XcodeServeProcessRecord(pid: 1, startTime: 0, executablePath: "/usr/bin/x8")
            try JSONEncoder().encode(staleRecord).write(to: pidFile)

            let storage = InMemoryStorage()
            let record = XcodeServeProcessRecord(pid: 42, startTime: 100, executablePath: "/usr/bin/x8")
            let runner = XcodeServeRunner(
                socketPath: directory.appending(path: "cache.sock").path,
                casStore: storage,
                actionCacheStore: storage,
                serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) },
                processRecord: record
            )

            let handle = try await runner.start()
            let decoded = XcodeServeRunner.readProcessRecord(at: pidFile)
            #expect(decoded == record)

            await handle.shutdown()
        }
    }

    @Test
    func shutdownRemovesClaimedPIDFile() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            let storage = InMemoryStorage()
            let record = XcodeServeProcessRecord(pid: 42, startTime: 100, executablePath: "/usr/bin/x8")
            let runner = XcodeServeRunner(
                socketPath: socket.path,
                casStore: storage,
                actionCacheStore: storage,
                serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) },
                processRecord: record
            )

            let handle = try await runner.start()
            let pidFile = directory.appending(path: "serve.pid")
            #expect(FileManager.default.fileExists(atPath: pidFile.path))

            await handle.shutdown()

            #expect(FileManager.default.fileExists(atPath: pidFile.path) == false)
        }
    }

    @Test
    func skipsPIDFileWhenNoProcessRecordIsGiven() async throws {
        try await withTempDirectory { directory in
            let socket = directory.appending(path: "cache.sock")
            let storage = InMemoryStorage()
            let runner = XcodeServeRunner(
                socketPath: socket.path,
                casStore: storage,
                actionCacheStore: storage,
                serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) }
            )

            let handle = try await runner.start()
            let pidFile = directory.appending(path: "serve.pid")
            #expect(FileManager.default.fileExists(atPath: pidFile.path) == false)

            await handle.shutdown()
        }
    }

    /// Runs `body` with a fresh temporary directory, removed afterward regardless of outcome.
    private func withTempDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// Opens and exclusively locks `url`, simulating another live process holding its pidfile.
    ///
    /// The returned descriptor must be closed to release the lock; a test
    /// that wants the lock held for its whole body should defer that close.
    private func lockPIDFile(at url: URL) -> Int32? {
        let descriptor = url.path.withCString { path in
            open(path, O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK, 0o600)
        }
        return descriptor >= 0 ? descriptor : nil
    }
}

private struct ImmediateTerminationSignalWaiter: TerminationSignalWaiting {
    func wait() async -> TerminationSignal? {
        .terminate
    }
}

private struct FailingRunningServer: XcodeCacheServing, Sendable {
    let socketPath: String

    func serve() async throws {
        throw ServerFailure()
    }

    func beginGracefulShutdown() {}
}

private struct NeverTerminationSignalWaiter: TerminationSignalWaiting {
    func wait() async -> TerminationSignal? {
        try? await Task.sleep(for: .seconds(60))
        return nil
    }
}

private struct ServerFailure: Error, Sendable {}
