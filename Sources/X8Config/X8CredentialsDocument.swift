/// The raw `s3.api.credentials` block.
package struct X8CredentialsDocument: Codable, Equatable, Sendable {
    /// `static` or `defaultChain`.
    package let source: String?

    /// The access key identifier for `static`.
    package let accessKeyID: String?

    /// The secret access key for `static`.
    package let secretAccessKey: String?

    /// The optional session token for `static`.
    package let sessionToken: String?

    /// Creates a raw credentials block without validating its values.
    package init(
        source: String? = nil,
        accessKeyID: String? = nil,
        secretAccessKey: String? = nil,
        sessionToken: String? = nil
    ) {
        self.source = source
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}
