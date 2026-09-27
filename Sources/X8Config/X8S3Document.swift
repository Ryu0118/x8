/// The raw `s3` block: shared signed API access plus the read and write paths.
package struct X8S3Document: Codable, Equatable, Sendable {
    /// Signed S3 API access shared by any path set to `api`.
    package let api: X8S3APIDocument?

    /// The read path: `api`, `none`, or a `publicURL` map.
    package let read: X8AccessPathDocument?

    /// The write path: `api` or `none`.
    package let write: X8AccessPathDocument?

    /// Creates a raw S3 block without validating its values.
    package init(api: X8S3APIDocument? = nil, read: X8AccessPathDocument? = nil, write: X8AccessPathDocument? = nil) {
        self.api = api
        self.read = read
        self.write = write
    }
}
