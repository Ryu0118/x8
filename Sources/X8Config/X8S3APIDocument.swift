/// The raw `s3.api` block.
package struct X8S3APIDocument: Codable, Equatable, Sendable {
    /// The optional S3-compatible endpoint.
    package let endpoint: String?

    /// The optional signing region.
    package let region: String?

    /// The bucket.
    package let bucket: String?

    /// The credential source and its fields.
    package let credentials: X8CredentialsDocument?

    /// Creates a raw API block without validating its values.
    package init(
        endpoint: String? = nil,
        region: String? = nil,
        bucket: String? = nil,
        credentials: X8CredentialsDocument? = nil
    ) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.credentials = credentials
    }
}
