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
