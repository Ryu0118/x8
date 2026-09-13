import Foundation
import X8Core
import X8Storage

/// Tracks one request's streamed bytes without sharing mutable counters across tasks.
package actor X8CacheByteCounter {
    private var total: Int64 = 0

    /// Adds one observed chunk, saturating rather than wrapping on overflow.
    package func add(_ count: Int) {
        let (next, overflow) = total.addingReportingOverflow(Int64(max(0, count)))
        total = overflow ? .max : next
    }

    /// Returns the accumulated byte count.
    package func value() -> Int64 {
        total
    }
}

/// Binds one RPC's operation, byte accounting, and latency to the shared recorder.
package struct X8CacheMetricContext: Sendable {
    private let operation: X8CacheMetricOperation
    private let metrics: any X8CacheMetricsRecorder
    private let counter: X8CacheByteCounter
    private let startedAt: ContinuousClock.Instant
    private let rpc: String?
    private let keyBytes: Data?

    /// Creates a request-scoped metrics context.
    ///
    /// - Parameters:
    ///   - rpc: The wire-level RPC name, for per-event observers only.
    ///   - keyBytes: The opaque CAS or Action Cache key bytes, for per-event
    ///     observers only. Aggregate recording ignores both.
    package init(
        operation: X8CacheMetricOperation,
        metrics: any X8CacheMetricsRecorder,
        rpc: String? = nil,
        keyBytes: Data? = nil
    ) {
        self.operation = operation
        self.metrics = metrics
        self.rpc = rpc
        self.keyBytes = keyBytes
        counter = X8CacheByteCounter()
        startedAt = ContinuousClock.now
    }

    /// Wraps a byte stream while preserving lazy consumption and back-pressure.
    package func observe(_ stream: ByteStream) -> ByteStream {
        ByteStreamSupport.observing(stream) { [counter] count in
            await counter.add(count)
        }
    }

    /// Accounts for opaque Action Cache entry bytes without decoding them.
    package func observe(_ value: ActionCacheValue) async {
        for entry in value.entries.values {
            await counter.add(entry.count)
        }
    }

    /// Records the completed outcome and the bytes consumed by this request.
    ///
    /// - Parameter keyBytes: Overrides the key passed to `init` for RPCs
    ///   (such as CAS `Put`/`Save`) whose key is only known once storage has
    ///   generated it. `nil` keeps whatever `init` was given.
    package func finish(
        outcome: X8CacheMetricOutcome,
        keyBytes: Data? = nil
    ) async {
        let byteCount = await counter.value()
        await metrics.record(
            X8CacheMetricsEvent(
                operation: operation,
                outcome: outcome,
                byteCount: byteCount,
                latency: startedAt.duration(to: .now),
                rpc: rpc,
                keyBytes: keyBytes ?? self.keyBytes
            )
        )
    }
}
