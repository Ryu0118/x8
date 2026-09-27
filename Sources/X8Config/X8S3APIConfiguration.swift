import Foundation

/// Validated signed S3 API access, shared by every path set to `api`.
package struct X8S3APIConfiguration: Equatable, Sendable {
    /// The optional S3-compatible endpoint; `nil` selects AWS's default.
    package let endpoint: URL?

    /// The signing region.
    package let region: String

    /// The bucket containing the cache.
    package let bucket: String

    /// Where credentials come from.
    package let credentials: X8CredentialSource

    /// Creates API access settings without performing validation.
    package init(
        endpoint: URL? = nil,
        region: String = "us-east-1",
        bucket: String,
        credentials: X8CredentialSource = .defaultChain
    ) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.credentials = credentials
    }
}
