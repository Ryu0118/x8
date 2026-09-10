import Foundation
import Testing
import X8Core
import X8Storage

@Suite("Consumer-only Action Cache storage rejects writes")
struct ConsumerOnlyActionCacheStoreTests {
    @Test
    func getValueDelegatesToWrappedStore() async throws {
        let wrapped = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x50]))
        let value = ActionCacheValue(entries: ["value": Data([0x01])])
        try await wrapped.putValue(value, for: key)
        let consumerOnly = ConsumerOnlyActionCacheStore(wrapping: wrapped)

        let loadedValue = try #require(try await consumerOnly.getValue(for: key))

        #expect(loadedValue == value)
    }

    @Test
    func putValueThrowsWithoutReachingWrappedStore() async throws {
        let wrapped = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x51]))
        let value = ActionCacheValue(entries: ["value": Data([0x02])])
        let consumerOnly = ConsumerOnlyActionCacheStore(wrapping: wrapped)

        await #expect(throws: CacheRoleError.writeNotAllowed) {
            try await consumerOnly.putValue(value, for: key)
        }

        #expect(try await wrapped.getValue(for: key) == nil)
    }
}
