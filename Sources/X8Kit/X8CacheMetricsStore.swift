import Foundation

/// Actor-isolated in-memory aggregation for one X8 proxy lifetime.
public actor X8CacheMetricsStore: X8CacheMetricsRecorder {
    private static let maximumLatencySamples = 2048

    private var getRequests: Int64 = 0
    private var putRequests: Int64 = 0
    private var cacheHits: Int64 = 0
    private var cacheMisses: Int64 = 0
    private var remoteErrors: Int64 = 0
    private var corruptedObjects: Int64 = 0
    private var bytesDownloaded: Int64 = 0
    private var bytesUploaded: Int64 = 0
    private var getLatencies: [Double] = []
    private var putLatencies: [Double] = []

    /// Creates an empty metrics store.
    public init() {}

    /// Records one operation and bounds retained latency samples.
    public func record(_ event: X8CacheMetricsEvent) async {
        switch event.operation {
        case .get:
            getRequests = increment(getRequests)
            bytesDownloaded = add(bytesDownloaded, event.byteCount)
            getLatencies.append(event.latency.milliseconds)
            trim(&getLatencies)
        case .put:
            putRequests = increment(putRequests)
            bytesUploaded = add(bytesUploaded, event.byteCount)
            putLatencies.append(event.latency.milliseconds)
            trim(&putLatencies)
        }

        switch event.outcome {
        case .hit:
            cacheHits = increment(cacheHits)
        case .miss:
            cacheMisses = increment(cacheMisses)
        case .remoteError:
            remoteErrors = increment(remoteErrors)
        case .corrupted:
            corruptedObjects = increment(corruptedObjects)
        case .stored:
            break
        }
    }

    /// Returns a snapshot with percentile calculations isolated to this actor.
    public func snapshot() async -> X8CacheMetricsSnapshot {
        X8CacheMetricsSnapshot(
            getRequests: getRequests,
            putRequests: putRequests,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            remoteErrors: remoteErrors,
            corruptedObjects: corruptedObjects,
            bytesDownloaded: bytesDownloaded,
            bytesUploaded: bytesUploaded,
            getLatencyP50Milliseconds: percentile(0.50, in: getLatencies),
            getLatencyP95Milliseconds: percentile(0.95, in: getLatencies),
            putLatencyP50Milliseconds: percentile(0.50, in: putLatencies),
            putLatencyP95Milliseconds: percentile(0.95, in: putLatencies)
        )
    }

    private func trim(_ samples: inout [Double]) {
        guard samples.count > Self.maximumLatencySamples else { return }
        samples.removeFirst(samples.count - Self.maximumLatencySamples)
    }

    private func percentile(_ ratio: Double, in samples: [Double]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = min(
            sorted.count - 1,
            max(0, Int(ceil(ratio * Double(sorted.count))) - 1)
        )
        return sorted[index]
    }

    private func increment(_ value: Int64) -> Int64 {
        value == .max ? .max : value + 1
    }

    private func add(_ value: Int64, _ amount: Int64) -> Int64 {
        let (result, overflow) = value.addingReportingOverflow(max(0, amount))
        return overflow ? .max : result
    }
}
