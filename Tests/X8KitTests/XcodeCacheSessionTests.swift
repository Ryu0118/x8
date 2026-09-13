import Foundation
import Testing
@testable import X8Kit
import X8Storage

@Suite("Xcode cache session lifecycle")
struct XcodeCacheSessionTests {
    @Test
    func startsWithCacheEnvironmentAndCleansUpOnShutdown() async throws {
        let storage = InMemoryStorage()
        let session = try await XcodeCacheSession.start(
            casStore: storage,
            actionCacheStore: storage,
            serverFactory: { socketPath, _, _, _ in
                TestCacheServer(socketPath: socketPath)
            }
        )
        let runtimeDirectory = URL(filePath: session.socketPath).deletingLastPathComponent()

        #expect(session.socketPath.hasSuffix("/cache.sock"))
        let otherMappings = "$(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built $(OBJROOT)/../..=/^dd $(WORKSPACE_DIR)=/^workspace"
        #expect(session.cacheEnvironment == [
            "COMPILATION_CACHE_ENABLE_CACHING": "YES",
            "COMPILATION_CACHE_ENABLE_PLUGIN": "YES",
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH": session.socketPath,
            "SWIFT_ENABLE_PREFIX_MAPPING": "YES",
            "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
            "CLANG_ENABLE_PREFIX_MAPPING": "YES",
            "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
            "SWIFT_OTHER_PREFIX_MAPPINGS": otherMappings,
            "CLANG_OTHER_PREFIX_MAPPINGS": otherMappings,
            "CLANG_MODULES_BUILD_SESSION_FILE": "",
        ])
        #expect(FileManager.default.fileExists(atPath: runtimeDirectory.path))

        await session.shutdown()
        await session.shutdown()

        #expect(FileManager.default.fileExists(atPath: runtimeDirectory.path) == false)
    }

    @Test
    func skipsTheEventsSocketWhenNoURLIsSupplied() async throws {
        let storage = InMemoryStorage()
        let session = try await XcodeCacheSession.start(
            casStore: storage,
            actionCacheStore: storage,
            serverFactory: { socketPath, _, _, _ in
                TestCacheServer(socketPath: socketPath)
            }
        )
        #expect(session.eventsSocketWarning == nil)
        await session.shutdown()
    }

    @Test
    func doesNotReturnWhenTheServerStopsBeforeReadiness() async throws {
        let storage = InMemoryStorage()

        do {
            _ = try await XcodeCacheSession.start(
                casStore: storage,
                actionCacheStore: storage,
                serverFactory: { socketPath, _, _, _ in
                    FailingCacheServer(socketPath: socketPath)
                }
            )
            Issue.record("Expected cache-server startup to fail before returning a session.")
        } catch let error as XcodeCacheServerError {
            #expect(error == .stoppedBeforeReady(socketPath: error.socketPath))
            let runtimeDirectory = URL(filePath: error.socketPath).deletingLastPathComponent()
            #expect(FileManager.default.fileExists(atPath: runtimeDirectory.path) == false)
        }
    }
}

private extension XcodeCacheServerError {
    var socketPath: String {
        switch self {
        case let .startupTimedOut(socketPath),
             let .stoppedBeforeReady(socketPath),
             let .socketPathOccupied(socketPath):
            socketPath
        }
    }
}

private struct FailingCacheServer: XcodeCacheServing, Sendable {
    let socketPath: String

    func serve() async throws {
        throw StartupFailure()
    }

    func beginGracefulShutdown() {}
}

private struct StartupFailure: Error, Sendable {}
