/// Raw, optional values decoded from an X8 YAML configuration document.
///
/// Optional values are intentional. The loader preserves the document, while
/// a higher-level resolver applies defaults, expansion, and validation. This
/// type does not represent a usable backend configuration until that resolver
/// stage succeeds.
public struct X8ConfigurationDocument: Codable, Equatable, Sendable {
    /// The configuration schema version, when present.
    public let version: Int?

    /// The optional S3-compatible endpoint.
    public let endpoint: String?

    /// The optional object-store signing region.
    public let region: String?

    /// The object-store bucket.
    public let bucket: String?

    /// Whether this invocation may push, pull, or both. Defaults to `.both`
    /// when absent.
    public let role: CacheRole?

    /// The optional access key identifier.
    public let accessKeyID: String?

    /// The optional secret access key.
    public let secretAccessKey: String?

    /// The optional session token.
    public let sessionToken: String?

    /// Creates a raw configuration document without validating its values.
    public init(
        version: Int? = nil,
        endpoint: String? = nil,
        region: String? = nil,
        bucket: String? = nil,
        role: CacheRole? = nil,
        accessKeyID: String? = nil,
        secretAccessKey: String? = nil,
        sessionToken: String? = nil
    ) {
        self.version = version
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.role = role
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}
