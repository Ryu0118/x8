import Foundation
import Testing
import X8Core
import X8Storage

@Suite("In-memory Action Cache storage")
struct InMemoryActionCacheStoreTests {
    @Test
    func missingValueReturnsNil() async throws {
        let storage = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x50]))

        let value = try await storage.getValue(for: key)

        #expect(value == nil)
    }

    @Test
    func putAndGetPreserveOpaqueValue() async throws {
        let storage = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x51, 0x52]))
        let value = ActionCacheValue(entries: [
            "value": Data([0x00, 0xFF]),
            "metadata": Data([0x61, 0x62]),
        ])

        try await storage.putValue(value, for: key)
        let loadedValue = try #require(try await storage.getValue(for: key))

        #expect(loadedValue == value)
    }

    @Test
    func putValueReplacesExistingValue() async throws {
        let storage = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x53]))
        let firstValue = ActionCacheValue(entries: ["value": Data([0x01])])
        let secondValue = ActionCacheValue(entries: ["value": Data([0x02])])

        try await storage.putValue(firstValue, for: key)
        try await storage.putValue(secondValue, for: key)
        let loadedValue = try #require(try await storage.getValue(for: key))

        #expect(loadedValue == secondValue)
    }
}
