#if X8_S3
    import Foundation
    import X8Config
    import X8Core

    /// Configuration for one S3-compatible X8 cache domain.
    ///
    /// The bucket identifies the object-key boundary used by the backend.
    /// This value only holds configuration and does not create an AWS
    /// client, access the network, or validate provider credentials.
    public struct S3StorageConfiguration: Equatable, Sendable {
        /// The bucket containing X8 records.
        public let bucket: String

        /// The AWS region or provider-specific signing region.
        public let region: String

        /// The optional endpoint for an S3-compatible service.
        public let endpoint: URL?

        /// The optional static credentials for this profile.
        public let credentials: RemoteCacheCredentials?

        /// The soft limit on concurrent HTTP/1.1 connections per host.
        ///
        /// R2 enforces roughly one write per second per object key; a wider
        /// connection pool lets many *different* keys make progress in
        /// parallel instead of queuing behind AsyncHTTPClient's default
        /// limit of 8, which starves large parallel builds and surfaces as
        /// `deadlineExceeded` rather than a provider error.
        public let maximumConnectionsPerHost: Int

        /// The maximum number of concurrent S3 operations (get and put)
        /// this storage instance issues at once.
        ///
        /// Keep this at or below `maximumConnectionsPerHost`: a wider
        /// semaphore than the connection pool just queues behind the pool
        /// again, reproducing the same starvation.
        public let maximumConcurrentOperations: Int

        /// Creates an S3 backend configuration.
        public init(
            bucket: String,
            region: String = "us-east-1",
            endpoint: URL? = nil,
            credentials: RemoteCacheCredentials? = nil,
            maximumConnectionsPerHost: Int = 64,
            maximumConcurrentOperations: Int = 64
        ) {
            self.bucket = bucket
            self.region = region
            self.endpoint = endpoint
            self.credentials = credentials
            self.maximumConnectionsPerHost = maximumConnectionsPerHost
            self.maximumConcurrentOperations = maximumConcurrentOperations
        }
    }
#endif
