import Foundation

/// Errors raised while locating and decoding X8 configuration documents.
///
/// These errors describe the loader boundary only. Schema value validation and
/// scalar expansion failures are reported separately by
/// `X8ConfigurationResolutionError`.
public enum X8ConfigurationLoadingError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No `.x8.yml` was found in the requested directory.
    case configurationFileNotFound(directory: URL)

    /// A configuration file could not be read.
    case configurationFileUnreadable(URL)

    /// A YAML document could not be decoded.
    case invalidYAML(URL)

    /// A document contains a key outside the supported schema.
    case unsupportedField(URL, String)

    /// A diagnostic description suitable for CLI output.
    public var description: String {
        switch self {
        case let .configurationFileNotFound(directory):
            "No .x8.yml found in \(directory.path)."
        case let .configurationFileUnreadable(url):
            "The X8 configuration at \(url.path) could not be read."
        case let .invalidYAML(url):
            "The X8 configuration at \(url.path) is not valid YAML."
        case let .unsupportedField(url, field):
            "The X8 configuration at \(url.path) contains unsupported field \(field)."
        }
    }
}
