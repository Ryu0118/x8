import Foundation
import Testing
import X8Core

@Suite("Action Cache values")
struct ActionCacheValueTests {
    @Test
    func preservesOpaqueEntries() {
        let entries = [
            "value": Data([0x00, 0x01]),
            "metadata": Data([0xFE, 0xFF]),
        ]

        let value = ActionCacheValue(entries: entries)

        #expect(value.entries == entries)
    }
}
