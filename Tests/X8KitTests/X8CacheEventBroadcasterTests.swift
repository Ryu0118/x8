import Foundation
import Testing
@testable import X8Kit

@Suite("Cache event fan-out to live subscribers")
struct X8CacheEventBroadcasterTests {
    @Test("forwards every recorded event to the wrapped recorder")
    func forwardsToWrapped() async {
        let wrapped = X8CacheMetricsStore()
        let broadcaster = X8CacheEventBroadcaster(wrapping: wrapped)

        await broadcaster.record(
            X8CacheMetricsEvent(operation: .get, outcome: .hit, byteCount: 4, latency: .milliseconds(1))
        )

        let snapshot = await broadcaster.snapshot()
        #expect(snapshot.getRequests == 1)
        #expect(snapshot.cacheHits == 1)
    }

    @Test("delivers recorded events to a live subscriber")
    func deliversToSubscriber() async {
        let broadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore())
        let stream = await broadcaster.subscribe()
        var iterator = stream.makeAsyncIterator()

        await broadcaster.record(
            X8CacheMetricsEvent(
                operation: .put,
                outcome: .stored,
                latency: .milliseconds(2),
                rpc: "cas.put",
                keyBytes: Data([0x01, 0x02])
            )
        )

        let event = await iterator.next()
        #expect(event?.rpc == "cas.put")
        #expect(event?.keyBytes == Data([0x01, 0x02]))
    }

    @Test("delivers independently to more than one subscriber")
    func deliversToMultipleSubscribers() async {
        let broadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore())
        let first = await broadcaster.subscribe()
        let second = await broadcaster.subscribe()
        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()

        await broadcaster.record(
            X8CacheMetricsEvent(operation: .get, outcome: .miss, latency: .milliseconds(1))
        )

        #expect(await firstIterator.next()?.outcome == .miss)
        #expect(await secondIterator.next()?.outcome == .miss)
    }

    @Test("drops the oldest buffered event for a subscriber that falls behind")
    func dropsOldestWhenBufferFull() async {
        let broadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore())
        let stream = await broadcaster.subscribe(bufferLimit: 1)

        await broadcaster.record(
            X8CacheMetricsEvent(operation: .get, outcome: .hit, latency: .milliseconds(1), rpc: "first")
        )
        await broadcaster.record(
            X8CacheMetricsEvent(operation: .get, outcome: .hit, latency: .milliseconds(1), rpc: "second")
        )

        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event?.rpc == "second")
    }
}
