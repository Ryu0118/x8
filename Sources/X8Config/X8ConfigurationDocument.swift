/// Raw, optional values decoded from an X8 YAML configuration document.
///
/// Optional values are intentional. The loader preserves the document, while
/// a higher-level resolver applies defaults, expansion, and validation. This
/// type does not represent a usable backend configuration until that resolver
/// stage succeeds.
package struct X8ConfigurationDocument: Codable, Equatable, Sendable {
    /// The configuration schema version, when present.
    package let version: Int?

    /// The S3 storage block, when present.
    package let s3: X8S3Document?

    /// The optional fixed Unix socket path for the cache proxy.
    ///
    /// Absent by default, in which case each command derives a per-user path
    /// from `profileID`. Set this to share one socket path across a team,
    /// typically with `$VAR` expansion (e.g. `${HOME}/.x8/cache.sock`) so the
    /// committed value still resolves per-user.
    package let socketPath: String?

    /// Creates a raw configuration document without validating its values.
    package init(version: Int? = nil, s3: X8S3Document? = nil, socketPath: String? = nil) {
        self.version = version
        self.s3 = s3
        self.socketPath = socketPath
    }
}
