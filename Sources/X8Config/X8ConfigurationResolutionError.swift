/// Errors raised while resolving a raw X8 configuration document.
///
/// Each description names the key path and how to fix it, without embedding
/// credential values, so it can safely be surfaced by a frontend.
package enum X8ConfigurationResolutionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The configuration schema version is not supported.
    case unsupportedVersion(Int)

    /// A required configuration field is absent.
    case missingField(String)

    /// A configuration field has an invalid value; `reason` says what is expected.
    case invalidField(String, reason: String)

    /// Both `s3.read` and `s3.write` are `none`.
    case readAndWriteDisabled

    /// `s3.read` or `s3.write` is `api` but `s3.api` is absent.
    case apiRequired(String)

    /// `s3.api` is configured but no path uses it.
    case unusedAPI

    /// `s3.write` asked for a public URL, which would allow anonymous writes.
    case publicURLWrite

    /// `static` credentials are missing the access key pair.
    case incompleteCredentials

    /// `defaultChain` credentials also carry static key fields.
    case defaultChainWithStaticFields

    /// A required environment variable was not available.
    case requiredEnvironmentVariable(String)

    /// The scalar contains a shell construct that X8 does not interpret.
    case unsupportedExpansion

    /// Nested parameter expansion exceeded the safety limit.
    case expansionDepthExceeded

    /// A diagnostic description that never includes secret values.
    package var description: String {
        switch self {
        case let .unsupportedVersion(version):
            "X8 configuration version \(version) is not supported; use version: 1."
        case let .missingField(field):
            "The X8 configuration is missing required field \(field)."
        case let .invalidField(field, reason):
            "The X8 configuration field \(field) is invalid: \(reason)."
        case .readAndWriteDisabled:
            "s3.read and s3.write are both none; set at least one of them to api (or s3.read to publicURL)."
        case let .apiRequired(field):
            "\(field) is api, but s3.api is not configured; add s3.api or change \(field)."
        case .unusedAPI:
            "s3.api is configured but neither s3.read nor s3.write is api; remove s3.api or set one of them to api."
        case .publicURLWrite:
            "s3.write cannot use a public URL because anonymous writes would let anyone poison the cache; use api or none."
        case .incompleteCredentials:
            "s3.api.credentials with source static requires both accessKeyID and secretAccessKey."
        case .defaultChainWithStaticFields:
            "s3.api.credentials with source defaultChain cannot also set accessKeyID, secretAccessKey, or sessionToken."
        case let .requiredEnvironmentVariable(name):
            "Required environment variable \(name) is not set."
        case .unsupportedExpansion:
            "The X8 configuration contains an unsupported parameter expansion."
        case .expansionDepthExceeded:
            "The X8 configuration contains excessively nested parameter expansion."
        }
    }
}
