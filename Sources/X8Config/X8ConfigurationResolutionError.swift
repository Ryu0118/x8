/// Errors raised while resolving a raw X8 configuration document.
///
/// Descriptions identify fields or syntax without embedding credential values,
/// so they can safely be surfaced by a frontend's diagnostics.
package enum X8ConfigurationResolutionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The configuration schema version is not supported.
    case unsupportedVersion(Int)

    /// A required configuration field is absent.
    case missingField(String)

    /// A configuration field has an invalid value.
    case invalidField(String)

    /// Exactly one static credential field was supplied.
    case incompleteCredentials

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
            "X8 configuration version \(version) is not supported."
        case let .missingField(field):
            "The X8 configuration is missing required field \(field)."
        case let .invalidField(field):
            "The X8 configuration field \(field) is invalid."
        case .incompleteCredentials:
            "Both accessKeyID and secretAccessKey must be supplied together."
        case let .requiredEnvironmentVariable(name):
            "Required environment variable \(name) is not set."
        case .unsupportedExpansion:
            "The X8 configuration contains an unsupported parameter expansion."
        case .expansionDepthExceeded:
            "The X8 configuration contains excessively nested parameter expansion."
        }
    }
}
