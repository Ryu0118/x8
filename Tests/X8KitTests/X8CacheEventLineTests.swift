import Foundation
import Testing
@testable import X8Kit

@Suite("NDJSON rendering of one cache traffic event")
struct X8CacheEventLineTests {
    @Test("renders every scalar field with a hex key prefix")
    func rendersFullEvent() {
        let event = X8CacheMetricsEvent(
            operation: .get,
            outcome: .hit,
            byteCount: 2048,
            latency: .milliseconds(12),
            rpc: "cas.get",
            keyBytes: Data([0xA3, 0xF9, 0xC1]),
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let line = X8CacheEventLine.line(for: event)

        #expect(line.contains("\"rpc\":\"cas.get\""))
        #expect(line.contains("\"outcome\":\"hit\""))
        #expect(line.contains("\"key\":\"a3f9c1\""))
        #expect(line.contains("\"bytes\":2048"))
        #expect(line.contains("\"latencyMs\":12.000"))
        #expect(!line.contains("\n"))
    }

    @Test("renders null for a missing rpc or key")
    func rendersMissingFieldsAsNull() {
        let event = X8CacheMetricsEvent(
            operation: .put,
            outcome: .stored,
            latency: .milliseconds(1)
        )

        let line = X8CacheEventLine.line(for: event)

        #expect(line.contains("\"rpc\":null"))
        #expect(line.contains("\"key\":null"))
    }

    @Test("truncates a longer key to the display prefix length")
    func truncatesLongKey() {
        let event = X8CacheMetricsEvent(
            operation: .get,
            outcome: .miss,
            latency: .milliseconds(1),
            keyBytes: Data(repeating: 0xFF, count: 32)
        )

        let line = X8CacheEventLine.line(for: event)

        let expectedPrefix = String(repeating: "ff", count: X8CacheEventLine.keyPrefixByteCount)
        #expect(line.contains("\"key\":\"\(expectedPrefix)\""))
    }
}
