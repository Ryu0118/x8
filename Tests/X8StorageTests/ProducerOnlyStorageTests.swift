import Foundation
import Testing
import X8Core
import X8Storage

@Suite("Producer-only storage suppresses reads and preserves writes")
struct ProducerOnlyStorageTests {
    @Test
    func suppressesReadsBeforeReachingBackend() async throws {
        let backend = ReadFailingStorage()
        let cas = ProducerOnlyCASStore(wrapping: backend)
        let actions = ProducerOnlyActionCacheStore(wrapping: backend)

        #expect(try await cas.get(id: CASDataID(rawValue: Data([1]))) == nil)
        #expect(try await cas.load(id: CASDataID(rawValue: Data([2]))) == nil)
        #expect(try await actions.getValue(for: ActionCacheKey(rawValue: Data([3]))) == nil)
    }

    @Test
    func preservesCASPayloadAndReferences() async throws {
        let backend = InMemoryStorage()
        let cas = ProducerOnlyCASStore(wrapping: backend)
        let reference = CASDataID(rawValue: Data([4]))
        let object = ByteStreamTestSupport.makeObject(
            chunks: [Data([1]), Data([2])],
            references: [reference]
        )

        let identifier = try await cas.put(object)
        let stored = try #require(try await backend.get(id: identifier))

        #expect(stored.references == [reference])
        #expect(try await ByteStreamTestSupport.collect(stored.bytes) == Data([1, 2]))
        #expect(try await cas.get(id: identifier) == nil)
    }

    @Test
    func preservesBlobPayload() async throws {
        let backend = InMemoryStorage()
        let cas = ProducerOnlyCASStore(wrapping: backend)
        let identifier = try await cas.save(
            ByteStreamTestSupport.makeStream(from: [Data([5]), Data([6])])
        )
        let stored = try #require(try await backend.load(id: identifier))

        #expect(try await ByteStreamTestSupport.collect(stored) == Data([5, 6]))
        #expect(try await cas.load(id: identifier) == nil)
    }

    @Test
    func preservesActionCacheValue() async throws {
        let backend = InMemoryStorage()
        let actions = ProducerOnlyActionCacheStore(wrapping: backend)
        let key = ActionCacheKey(rawValue: Data([7]))
        let value = ActionCacheValue(entries: ["value": Data([8])])

        try await actions.putValue(value, for: key)

        #expect(try await backend.getValue(for: key) == value)
        #expect(try await actions.getValue(for: key) == nil)
    }

    @Test
    func composingRestrictionsDisablesAllOperations() async throws {
        let backend = ReadFailingStorage()
        let cas = ProducerOnlyCASStore(wrapping: ConsumerOnlyCASStore(wrapping: backend))
        let actions = ProducerOnlyActionCacheStore(wrapping: ConsumerOnlyActionCacheStore(wrapping: backend))

        #expect(try await cas.get(id: CASDataID(rawValue: Data([1]))) == nil)
        #expect(try await cas.load(id: CASDataID(rawValue: Data([1]))) == nil)
        #expect(try await actions.getValue(for: ActionCacheKey(rawValue: Data([1]))) == nil)
        await #expect(throws: CacheRoleError.writeNotAllowed) {
            try await cas.put(ByteStreamTestSupport.makeObject(chunks: [], references: []))
        }
        await #expect(throws: CacheRoleError.writeNotAllowed) {
            try await cas.save(ByteStreamTestSupport.makeStream(from: []))
        }
        await #expect(throws: CacheRoleError.writeNotAllowed) {
            try await actions.putValue(
                ActionCacheValue(entries: [:]),
                for: ActionCacheKey(rawValue: Data([1]))
            )
        }
    }
}

private struct ReadFailingStorage: CASStore, ActionCacheStore {
    private let storage = InMemoryStorage()

    func get(id _: CASDataID) async throws -> CASObject? {
        throw ReadError.unexpectedRead
    }

    func load(id _: CASDataID) async throws -> ByteStream? {
        throw ReadError.unexpectedRead
    }

    func getValue(for _: ActionCacheKey) async throws -> ActionCacheValue? {
        throw ReadError.unexpectedRead
    }

    func put(_ object: CASObject) async throws -> CASDataID {
        try await storage.put(object)
    }

    func save(_ bytes: ByteStream) async throws -> CASDataID {
        try await storage.save(bytes)
    }

    func putValue(_ value: ActionCacheValue, for key: ActionCacheKey) async throws {
        try await storage.putValue(value, for: key)
    }

    private enum ReadError: Error {
        case unexpectedRead
    }
}
