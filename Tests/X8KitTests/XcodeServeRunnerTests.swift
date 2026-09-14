import Foundation
import Testing
@testable import X8Kit
import X8Storage

@Suite("Xcode standalone server socket ownership")
struct XcodeServeRunnerTests {
    @Test
    func refusesToReplaceExistingSocketPathWithAlivePIDFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: socket.path, contents: nil)
        try writePIDFile(inDirectory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = InMemoryStorage()
        let runner = XcodeServeRunner(
            socketPath: socket.path,
            casStore: storage,
            actionCacheStore: storage,
            livenessProbe: AlwaysAliveProcessLivenessProbe()
        )

        do {
            _ = try await runner.start()
            Issue.record("Expected an existing socket path to be rejected.")
        } catch let error as XcodeCacheServerError {
            #expect(error == .socketPathOccupied(socketPath: socket.path))
        } catch {
            Issue.record("Expected a socket-path error, got \(error).")
        }
    }

    @Test
    func reclaimsStaleSocketWithNoPIDFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: socket.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = InMemoryStorage()
        let runner = XcodeServeRunner(
            socketPath: socket.path,
            casStore: storage,
            actionCacheStore: storage,
            serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) },
            livenessProbe: AlwaysDeadProcessLivenessProbe()
        )

        let handle = try await runner.start()
        #expect(handle.socketPath == socket.path)
        await handle.shutdown()
    }

    @Test
    func reclaimsStaleSocketWithDeadPIDFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: socket.path, contents: nil)
        try writePIDFile(inDirectory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = InMemoryStorage()
        let runner = XcodeServeRunner(
            socketPath: socket.path,
            casStore: storage,
            actionCacheStore: storage,
            serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) },
            livenessProbe: AlwaysDeadProcessLivenessProbe()
        )

        let handle = try await runner.start()
        #expect(handle.socketPath == socket.path)
        await handle.shutdown()
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
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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

    @Test
    func terminationSignalWaitUsesInjectedWaiterAndShutsDown() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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

    @Test
    func cancellationWaitsForShutdownThenPropagates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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

    @Test
    func serverFailureStillTriggersGracefulCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: socket.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: directory) }

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

    @Test
    func droppedHandleCleansUpAfterServerStops() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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

    @Test
    func claimsPIDFileForDetachedProcessOnStart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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
        let data = try #require(FileManager.default.contents(atPath: pidFile.path))
        let decoded = try JSONDecoder().decode(XcodeServeProcessRecord.self, from: data)
        #expect(decoded == record)

        await handle.shutdown()
    }

    @Test
    func refusesToClaimPIDFileWhenAliveRecordAlreadyExists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writePIDFile(inDirectory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = InMemoryStorage()
        let record = XcodeServeProcessRecord(pid: 42, startTime: 100, executablePath: "/usr/bin/x8")
        let runner = XcodeServeRunner(
            socketPath: directory.appending(path: "cache.sock").path,
            casStore: storage,
            actionCacheStore: storage,
            serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) },
            livenessProbe: AlwaysAliveProcessLivenessProbe(),
            processRecord: record
        )

        do {
            _ = try await runner.start()
            Issue.record("Expected a live pidfile owner to refuse the claim.")
        } catch let error as XcodeCacheServerError {
            #expect(error == .socketPathOccupied(socketPath: directory.appending(path: "cache.sock").path))
        } catch {
            Issue.record("Expected a socket-path error, got \(error).")
        }
    }

    @Test
    func reclaimsPIDFileWhenExistingRecordIsDead() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writePIDFile(inDirectory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = InMemoryStorage()
        let record = XcodeServeProcessRecord(pid: 42, startTime: 100, executablePath: "/usr/bin/x8")
        let runner = XcodeServeRunner(
            socketPath: directory.appending(path: "cache.sock").path,
            casStore: storage,
            actionCacheStore: storage,
            serverFactory: { socketPath, _, _, _ in TestCacheServer(socketPath: socketPath) },
            livenessProbe: AlwaysDeadProcessLivenessProbe(),
            processRecord: record
        )

        let handle = try await runner.start()
        let pidFile = directory.appending(path: "serve.pid")
        let data = try #require(FileManager.default.contents(atPath: pidFile.path))
        let decoded = try JSONDecoder().decode(XcodeServeProcessRecord.self, from: data)
        #expect(decoded == record)

        await handle.shutdown()
    }

    @Test
    func shutdownRemovesClaimedPIDFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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

    @Test
    func skipsPIDFileWhenNoProcessRecordIsGiven() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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

    private func writePIDFile(inDirectory directory: URL) throws {
        let record = XcodeServeProcessRecord(pid: 1, startTime: 0, executablePath: "/usr/bin/x8")
        let data = try JSONEncoder().encode(record)
        try data.write(to: directory.appending(path: "serve.pid"))
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

private struct AlwaysDeadProcessLivenessProbe: ProcessLivenessProbing {
    func isAlive(_: XcodeServeProcessRecord) -> Bool {
        false
    }
}
