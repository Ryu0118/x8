/// A serializable snapshot of cache traffic observed by one proxy.
package struct X8CacheMetricsSnapshot: Codable, Equatable, Sendable {
    /// The number of read operations.
    package let getRequests: Int64

    /// The number of write operations.
    package let putRequests: Int64

    /// The number of successful cache reads.
    package let cacheHits: Int64

    /// The number of cache misses.
    package let cacheMisses: Int64

    /// The number of provider or storage errors.
    package let remoteErrors: Int64

    /// The number of records rejected as corrupt.
    package let corruptedObjects: Int64

    /// The number of bytes returned by reads.
    package let bytesDownloaded: Int64

    /// The number of bytes accepted by writes.
    package let bytesUploaded: Int64

    /// The p50 read latency in milliseconds, or nil when no read occurred.
    package let getLatencyP50Milliseconds: Double?

    /// The p95 read latency in milliseconds, or nil when no read occurred.
    package let getLatencyP95Milliseconds: Double?

    /// The p50 write latency in milliseconds, or nil when no write occurred.
    package let putLatencyP50Milliseconds: Double?

    /// The p95 write latency in milliseconds, or nil when no write occurred.
    package let putLatencyP95Milliseconds: Double?

    /// Creates a metrics snapshot.
    package init(
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
