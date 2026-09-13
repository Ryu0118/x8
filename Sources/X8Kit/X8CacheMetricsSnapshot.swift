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
