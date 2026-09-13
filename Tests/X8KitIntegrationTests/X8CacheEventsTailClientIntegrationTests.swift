import Foundation
import Testing
@testable import X8Kit

@Suite("Live cache-events tail client")
struct X8CacheEventsTailClientIntegrationTests {
    @Test("streams multiple recorded events as separate lines, in order")
    func streamsMultipleEventsInOrder() async throws {
        let path = temporarySocketPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let broadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore())
        guard case let .started(listenerTask) = await X8CacheEventsListener(broadcaster: broadcaster).start(at: path)
        else {
            Issue.record("Expected the events socket to start.")
            return
        }
        defer { listenerTask.cancel() }

        let stream = try await X8CacheEventsTailClient().connect(to: path)
        var iterator = stream.makeAsyncIterator()

        // Give the server a moment to register the new subscriber before recording.
        try await Task.sleep(for: .milliseconds(50))
        await broadcaster.record(
            X8CacheMetricsEvent(operation: .get, outcome: .hit, latency: .milliseconds(1), rpc: "first")
        )
        await broadcaster.record(
            X8CacheMetricsEvent(operation: .put, outcome: .stored, latency: .milliseconds(1), rpc: "second")
        )

        let first = try await iterator.next()
        let second = try await iterator.next()

        #expect(first?.contains("\"rpc\":\"first\"") == true)
        #expect(second?.contains("\"rpc\":\"second\"") == true)
    }

    @Test("throws when no listener is bound at the path")
    func throwsWhenNoListener() async throws {
        let path = temporarySocketPath()

        await #expect(throws: (any Error).self) {
            _ = try await X8CacheEventsTailClient().connect(to: path)
        }
    }

    private func temporarySocketPath() -> String {
        FileManager.default.temporaryDirectory
            .appending(path: "x8-tail-\(UUID().uuidString).sock")
            .path
    }
}
