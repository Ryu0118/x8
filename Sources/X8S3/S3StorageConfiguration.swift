#if X8_S3
    import Foundation
    import X8Config
    import X8Core

    /// Configuration for one S3-compatible X8 cache domain.
    ///
    /// Signed S3 API access and an unsigned public read URL are independent:
    /// at least one must be present. Xcode-path reads use the public URL when
    /// it is set and the signed API otherwise; writes, administration, and
    /// retention always require the signed API. This value only holds
    /// configuration and does not create a client, access the network, or
    /// validate provider credentials.
    package struct S3StorageConfiguration: Equatable, Sendable {
        /// The signed S3 API access, or `nil` for a public-read-only profile.
        package let api: S3APIConfiguration?

        /// The public object URL prefix used for unsigned reads, ending in `/`.
        package let publicReadURL: URL?

        /// The soft limit on concurrent HTTP/1.1 connections per host.
        ///
        /// R2 enforces roughly one write per second per object key; a wider
        /// connection pool lets many *different* keys make progress in
        /// parallel instead of queuing behind AsyncHTTPClient's default
        /// limit of 8, which starves large parallel builds and surfaces as
        /// `deadlineExceeded` rather than a provider error.
        package let maximumConnectionsPerHost: Int

        /// The maximum number of concurrent operations (get and put) this
        /// storage instance issues at once on each client.
        ///
        /// Keep this at or below `maximumConnectionsPerHost`: a wider
        /// semaphore than the connection pool just queues behind the pool
        /// again, reproducing the same starvation.
        package let maximumConcurrentOperations: Int

        /// Creates a backend configuration from signed API access and/or a public read URL.
        ///
        /// - Precondition: `api` or `publicReadURL` is non-`nil`.
        package init(
            api: S3APIConfiguration?,
            publicReadURL: URL? = nil,
            maximumConnectionsPerHost: Int = 64,
            maximumConcurrentOperations: Int = 64
        ) {
            precondition(api != nil || publicReadURL != nil, "S3 storage needs signed API access or a public read URL")
            self.api = api
            self.publicReadURL = publicReadURL
            self.maximumConnectionsPerHost = maximumConnectionsPerHost
            self.maximumConcurrentOperations = maximumConcurrentOperations
        }

        /// Creates a signed-API-only configuration.
        package init(
            bucket: String,
            region: String = "us-east-1",
            endpoint: URL? = nil,
            credentials: RemoteCacheCredentials? = nil
        ) {
            self.init(
                api: S3APIConfiguration(
                    bucket: bucket,
                    region: region,
                    endpoint: endpoint,
                    credentials: credentials
                )
            )
        }
    }
#endif
