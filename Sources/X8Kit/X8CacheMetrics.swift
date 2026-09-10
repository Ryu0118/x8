import Foundation

/// Identifies the direction of one cache operation observed by the proxy.
public enum X8CacheMetricOperation: String, Codable, Sendable {
    /// A CAS or Action Cache read.
    case get

    /// A CAS or Action Cache write.
    case put
}

/// Classifies the result of one cache operation.
public enum X8CacheMetricOutcome: String, Codable, Sendable {
    /// The requested cache record was returned.
    case hit

    /// The requested cache record did not exist.
    case miss

    /// The provider or storage implementation failed.
    case remoteError

    /// A provider record could not be decoded safely.
    case corrupted

    /// A write completed successfully.
    case stored
}

/// Describes one completed cache operation for metrics aggregation.
public struct X8CacheMetricsEvent: Sendable {
    /// The operation direction.
    public let operation: X8CacheMetricOperation

    /// The operation outcome.
    public let outcome: X8CacheMetricOutcome

    /// The number of payload bytes transferred, if known.
    public let byteCount: Int64

    /// The elapsed operation time.
    public let latency: Duration

    /// Creates a metrics event.
    public init(
        operation: X8CacheMetricOperation,
        outcome: X8CacheMetricOutcome,
        byteCount: Int64 = 0,
        latency: Duration
    ) {
        self.operation = operation
        self.outcome = outcome
        self.byteCount = max(0, byteCount)
        self.latency = latency
    }
}

/// A serializable snapshot of cache traffic observed by one proxy.
public struct X8CacheMetricsSnapshot: Codable, Equatable, Sendable {
    /// The number of read operations.
    public let getRequests: Int64

    /// The number of write operations.
    public let putRequests: Int64

    /// The number of successful cache reads.
    public let cacheHits: Int64

    /// The number of cache misses.
    public let cacheMisses: Int64

    /// The number of provider or storage errors.
    public let remoteErrors: Int64

    /// The number of records rejected as corrupt.
    public let corruptedObjects: Int64

    /// The number of bytes returned by reads.
    public let bytesDownloaded: Int64

    /// The number of bytes accepted by writes.
    public let bytesUploaded: Int64

    /// The p50 read latency in milliseconds, or nil when no read occurred.
    public let getLatencyP50Milliseconds: Double?

    /// The p95 read latency in milliseconds, or nil when no read occurred.
    public let getLatencyP95Milliseconds: Double?

    /// The p50 write latency in milliseconds, or nil when no write occurred.
    public let putLatencyP50Milliseconds: Double?

    /// The p95 write latency in milliseconds, or nil when no write occurred.
    public let putLatencyP95Milliseconds: Double?

    /// Creates a metrics snapshot.
    public init(
        getRequests: Int64,
        putRequests: Int64,
        cacheHits: Int64,
        cacheMisses: Int64,
        remoteErrors: Int64,
        corruptedObjects: Int64,
        bytesDownloaded: Int64,
        bytesUploaded: Int64,
        getLatencyP50Milliseconds: Double?,
        getLatencyP95Milliseconds: Double?,
        putLatencyP50Milliseconds: Double?,
        putLatencyP95Milliseconds: Double?
    ) {
        self.getRequests = getRequests
        self.putRequests = putRequests
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.remoteErrors = remoteErrors
        self.corruptedObjects = corruptedObjects
        self.bytesDownloaded = bytesDownloaded
        self.bytesUploaded = bytesUploaded
        self.getLatencyP50Milliseconds = getLatencyP50Milliseconds
        self.getLatencyP95Milliseconds = getLatencyP95Milliseconds
        self.putLatencyP50Milliseconds = putLatencyP50Milliseconds
        self.putLatencyP95Milliseconds = putLatencyP95Milliseconds
    }
}

/// Renders persisted metrics using stable, script-friendly field names.
public enum X8CacheMetricsPresentation {
    /// Returns one `name=value` line for every required cache metric.
    public static func render(_ snapshot: X8CacheMetricsSnapshot) -> String {
        [
            "get_requests=\(snapshot.getRequests)",
            "put_requests=\(snapshot.putRequests)",
            "cache_hits=\(snapshot.cacheHits)",
            "cache_misses=\(snapshot.cacheMisses)",
            "remote_errors=\(snapshot.remoteErrors)",
            "corrupted_objects=\(snapshot.corruptedObjects)",
            "bytes_downloaded=\(snapshot.bytesDownloaded)",
            "bytes_uploaded=\(snapshot.bytesUploaded)",
            "get_latency_p50=\(format(snapshot.getLatencyP50Milliseconds))",
            "get_latency_p95=\(format(snapshot.getLatencyP95Milliseconds))",
            "put_latency_p50=\(format(snapshot.putLatencyP50Milliseconds))",
            "put_latency_p95=\(format(snapshot.putLatencyP95Milliseconds))",
        ].joined(separator: "\n")
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.3fms", value)
    }
}

/// Receives completed proxy operations and exposes a consistent snapshot.
public protocol X8CacheMetricsRecorder: Sendable {
    /// Records one completed operation.
    func record(_ event: X8CacheMetricsEvent) async

    /// Returns the current aggregate snapshot.
    func snapshot() async -> X8CacheMetricsSnapshot
}

package extension Duration {
    /// Converts an elapsed duration to the unit used by persisted metrics.
    var milliseconds: Double {
        let components = components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1e15
    }
}
