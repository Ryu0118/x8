import Foundation
import Testing
@testable import X8CLI
import X8Core
import X8Storage

@Suite("Storage ownership ends once after operations finish")
struct X8StorageScopeTests {
    @Test
    func closesAfterSuccessfulOperation() async throws {
        let recorder = CLIRecorder()
        let scope = X8StorageScope(storage: InMemoryStorage(), shutdown: { _ in recorder.record("close") })
        let value = try await scope.withStorage { _ in
            recorder.record("operation")
            return 42
        }
        #expect(value == 42)
        #expect(recorder.events == ["operation", "close"])
    }

    @Test
    func retainsOriginalFailureWhenCleanupFails() async {
        let recorder = CLIRecorder()
        let scope = X8StorageScope(storage: InMemoryStorage(), shutdown: { _ in
            recorder.record("close")
            throw ScopeFailure.cleanup
        })
        await #expect(throws: ScopeFailure.operation) {
            try await scope.withStorage { _ in throw ScopeFailure.operation }
        }
        #expect(recorder.events == ["close"])
    }

    @Test
    func reportsCleanupFailureWithoutRetryingShutdown() async {
        let recorder = CLIRecorder()
        let scope = X8StorageScope(storage: InMemoryStorage(), shutdown: { _ in
            recorder.record("close")
            throw ScopeFailure.cleanup
        })
        await #expect(throws: ScopeFailure.cleanup) {
            try await scope.withStorage { _ in 42 }
        }
        #expect(recorder.events == ["close"])
    }

    @Test
    func closesBeforePropagatingCancellation() async {
        let recorder = CLIRecorder()
        let ready = AsyncStream<Void>.makeStream()
        let scope = X8StorageScope(storage: InMemoryStorage(), shutdown: { _ in recorder.record("close") })
        let task = Task {
            try await scope.withStorage { _ in
                ready.continuation.yield(())
                try await Task.sleep(for: .seconds(60))
            }
        }
        var iterator = ready.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(recorder.events == ["close"])
        ready.continuation.finish()
    }

    @Test
    func closesStorageReturnedDuringCancellation() async {
        let recorder = CLIRecorder()
        let scope = X8StorageScope(storage: InMemoryStorage(), shutdown: { _ in recorder.record("close") })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await scope.withStorage { _ in recorder.record("operation") }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(recorder.events == ["close"])
    }

    @Test
    func appliesProducerAndConsumerPermissionsToBothStores() async throws {
        let storage = InMemoryStorage()
        let scope = X8StorageScope(storage: storage, shutdown: { _ in })
        let key = ActionCacheKey(rawValue: Data([1]))
        let value = ActionCacheValue(entries: ["value": Data([2])])
        try await storage.putValue(value, for: key)
        let id = try await storage.save(ByteStreamSupport.make(Data([3])))

        #expect(try await scope.actionCacheStore(role: .producer).getValue(for: key) == nil)
        #expect(try await scope.casStore(role: .producer).get(id: id) == nil)
        #expect(try await scope.actionCacheStore(role: .consumer).getValue(for: key) == value)
        #expect(try await scope.casStore(role: .consumer).get(id: id) != nil)
        await #expect(throws: CacheRoleError.writeNotAllowed) {
            try await scope.actionCacheStore(role: .consumer).putValue(value, for: key)
        }
        await #expect(throws: CacheRoleError.writeNotAllowed) {
            try await scope.casStore(role: .consumer).save(ByteStreamSupport.make(Data()))
        }
    }
}

private enum ScopeFailure: Error {
    case operation
    case cleanup
}
