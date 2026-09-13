import Foundation
import Testing
@testable import X8CLI
import X8Kit

@Suite("Tail line rendering for terminal display")
struct TailLineFormatterTests {
    @Test("renders a decodable line with every field present")
    func rendersFullLine() {
        let event = X8CacheMetricsEvent(
            operation: .get,
            outcome: .hit,
            byteCount: 2048,
            latency: .milliseconds(12),
            rpc: "cas.get",
            keyBytes: Data([0xA3, 0xF9, 0xC1]),
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let rendered = TailLineFormatter.render(X8CacheEventLine.line(for: event))

        #expect(rendered.contains("HIT"))
        #expect(rendered.contains("cas.get"))
        #expect(rendered.contains("a3f9c1…"))
        #expect(rendered.contains("2048B"))
        #expect(rendered.contains("12ms"))
    }

    @Test("falls back to the raw line when it does not decode")
    func fallsBackForUndecodableLine() {
        let rendered = TailLineFormatter.render("not json")

        #expect(rendered == "not json")
    }

    @Test("shows placeholders for a missing rpc or key")
    func rendersPlaceholdersForMissingFields() {
        let event = X8CacheMetricsEvent(
            operation: .put,
            outcome: .stored,
            latency: .milliseconds(1)
        )

        let rendered = TailLineFormatter.render(X8CacheEventLine.line(for: event))

        #expect(rendered.contains(" - "))
    }
}
