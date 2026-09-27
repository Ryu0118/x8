#if X8_S3
    import Foundation
    import X8Config

    /// Signed S3 API access for one bucket.
    package struct S3APIConfiguration: Equatable, Sendable {
        /// The bucket containing X8 records.
        package let bucket: String

        /// The AWS region or provider-specific signing region.
        package let region: String

        /// The optional endpoint for an S3-compatible service.
        package let endpoint: URL?

        /// Static credentials, or `nil` to use Soto's default provider chain.
        package let credentials: RemoteCacheCredentials?

        /// Creates signed API access settings.
        package init(
            bucket: String,
            region: String = "us-east-1",
            endpoint: URL? = nil,
            credentials: RemoteCacheCredentials? = nil
        ) {
            self.bucket = bucket
            self.region = region
            self.endpoint = endpoint
            self.credentials = credentials
        }
    }
#endif
