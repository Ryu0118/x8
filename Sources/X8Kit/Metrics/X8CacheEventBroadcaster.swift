import Foundation

/// Fans a recorded metrics event out to zero or more live subscribers.
///
/// This actor wraps an existing ``X8CacheMetricsRecorder`` without changing
/// its aggregation behavior: every event is forwarded to the wrapped recorder
/// first, then to each subscriber's stream. Subscribers exist for per-event
/// observers such as a live tail; they never affect `snapshot()`.
package actor X8CacheEventBroadcaster: X8CacheMetricsRecorder {
    private let wrapped: any X8CacheMetricsRecorder
    private var subscribers: [UUID: AsyncStream<X8CacheMetricsEvent>.Continuation] = [:]

    /// Creates a broadcaster that also forwards every event to `wrapped`.
    package init(wrapping wrapped: any X8CacheMetricsRecorder) {
        self.wrapped = wrapped
    }

    /// Records the event with the wrapped recorder, then delivers it live.
    ///
    /// Delivery is best-effort: each subscriber has a small bounded buffer,
    /// and a slow subscriber drops its oldest buffered event rather than
    /// applying backpressure to the RPC path that produced this event.
    package func record(_ event: X8CacheMetricsEvent) async {
        await wrapped.record(event)
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    /// Returns the wrapped recorder's aggregate snapshot, unchanged.
    package func snapshot() async -> X8CacheMetricsSnapshot {
        await wrapped.snapshot()
    }

    /// Subscribes to future events until the returned stream is discarded.
    ///
    /// - Parameter bufferLimit: The number of most-recent events retained for
    ///   a subscriber that is not keeping up; older events are dropped first.
    package func subscribe(bufferLimit: Int = 64) -> AsyncStream<X8CacheMetricsEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(bufferLimit)) { continuation in
            subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
