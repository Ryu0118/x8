import Foundation
import Testing
@testable import X8Kit
import X8Storage

@Suite("Xcode standalone server socket ownership")
struct XcodeServeRunnerTests {
    @Test
    func refusesToReplaceExistingSocketPath() async throws {
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
            actionCacheStore: storage
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
    func activatedSessionLeavesSupervisorOwnedSocketInPlace() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-serve-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let socket = directory.appending(path: "cache.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runtimeDirectory = XcodeCacheRuntimeDirectory(
            url: directory,
            fileManager: FileManager.default
        )
        let storage = InMemoryStorage()
        let lifecycle = XcodeCacheServerLifecycle()
        let session = try await lifecycle.startActivated(
            runtimeDirectory: runtimeDirectory,
            listeningSocketDescriptor: 123,
            casStore: storage,
            actionCacheStore: storage,
            serverFactory: { socketPath, _, _, _, _ in
                TestCacheServer(socketPath: socketPath)
            }
        )
        let handle = try XcodeServeHandle(session: session)

        await handle.shutdown()

        #expect(FileManager.default.fileExists(atPath: socket.path))
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
