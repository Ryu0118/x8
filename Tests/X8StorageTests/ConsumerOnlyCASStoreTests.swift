import Foundation
import Testing
import X8Core
import X8Storage

@Suite("Consumer-only CAS storage rejects writes")
struct ConsumerOnlyCASStoreTests {
    @Test
    func getDelegatesToWrappedStore() async throws {
        let wrapped = InMemoryStorage()
        let identifier = try await wrapped.put(
            ByteStreamTestSupport.makeObject(
                chunks: [Data([0x01, 0x02])],
                references: []
            )
        )
        let consumerOnly = ConsumerOnlyCASStore(wrapping: wrapped)

        let object = try #require(try await consumerOnly.get(id: identifier))
        let content = try await ByteStreamTestSupport.collect(object.bytes)

        #expect(content == Data([0x01, 0x02]))
    }

    @Test
    func loadDelegatesToWrappedStore() async throws {
        let wrapped = InMemoryStorage()
        let identifier = try await wrapped.save(
            ByteStreamTestSupport.makeStream(from: [Data([0x03, 0x04])])
        )
        let consumerOnly = ConsumerOnlyCASStore(wrapping: wrapped)

        let stream = try #require(try await consumerOnly.load(id: identifier))
        let content = try await ByteStreamTestSupport.collect(stream)

        #expect(content == Data([0x03, 0x04]))
    }

    @Test
    func putThrowsWithoutReachingWrappedStore() async throws {
        let wrapped = InMemoryStorage()
        let consumerOnly = ConsumerOnlyCASStore(wrapping: wrapped)
        let object = ByteStreamTestSupport.makeObject(
            chunks: [Data([0x05])],
            references: []
        )

        await #expect(throws: CacheRoleError.writeNotAllowed) {
            _ = try await consumerOnly.put(object)
        }

        let expectedID = CASDataIDGenerator.id(for: Data([0x05]), references: [])
        #expect(try await wrapped.get(id: expectedID) == nil)
    }

    @Test
    func saveThrowsWithoutReachingWrappedStore() async throws {
        let wrapped = InMemoryStorage()
        let consumerOnly = ConsumerOnlyCASStore(wrapping: wrapped)

        await #expect(throws: CacheRoleError.writeNotAllowed) {
            _ = try await consumerOnly.save(
                ByteStreamTestSupport.makeStream(from: [Data([0x06])])
            )
        }

        let expectedID = CASDataIDGenerator.id(for: Data([0x06]), references: [])
        #expect(try await wrapped.load(id: expectedID) == nil)
    }
}
