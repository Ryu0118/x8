import Foundation

/// Describes one completed cache operation for metrics aggregation.
package struct X8CacheMetricsEvent: Sendable {
    /// The operation direction.
    package let operation: X8CacheMetricOperation

    /// The operation outcome.
    package let outcome: X8CacheMetricOutcome

    /// The number of payload bytes transferred, if known.
    package let byteCount: Int64

    /// The elapsed operation time.
    package let latency: Duration

    /// The wire-level RPC name, when the caller has one to report.
    ///
    /// Aggregate consumers such as ``X8CacheMetricsStore`` ignore this field;
    /// it exists for per-event observers such as a live tail.
    package let rpc: String?

    /// The opaque CAS or Action Cache key bytes, when the caller has one.
    ///
    /// Kept as raw bytes rather than re-derived: CAS identifiers are opaque
    /// per the project's cache-key contract, so a display surface truncates
    /// these bytes to a hex prefix instead of hashing or reinterpreting them.
    package let keyBytes: Data?

    /// When this operation completed.
    package let timestamp: Date

    /// Creates a metrics event.
    package init(
        operation: X8CacheMetricOperation,
        outcome: X8CacheMetricOutcome,
        byteCount: Int64 = 0,
        latency: Duration,
        rpc: String? = nil,
        keyBytes: Data? = nil,
        timestamp: Date = Date()
    ) {
        self.operation = operation
        self.outcome = outcome
        self.byteCount = max(0, byteCount)
        self.latency = latency
        self.rpc = rpc
        self.keyBytes = keyBytes
        self.timestamp = timestamp
    }
}
