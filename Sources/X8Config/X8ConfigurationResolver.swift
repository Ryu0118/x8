import Foundation

/// Resolves a raw configuration document into a validated runtime-neutral profile.
///
/// This is the in-memory stage after loading. It applies the schema version,
/// environment expansion, defaults, and validation of `s3.api`, `s3.read`,
/// and `s3.write` together, then returns `X8Configuration`. It performs no
/// file or network I/O and never constructs a storage provider or resolves
/// credentials. The supplied environment is copied into an isolated
/// expansion context, so assignment expressions cannot mutate the caller's
/// process environment.
package struct X8ConfigurationResolver: Sendable {
    /// Creates a configuration resolver.
    package init() {}

    /// Expands, validates, and resolves a raw configuration document.
    ///
    /// - Parameters:
    ///   - document: The optional raw values decoded by
    ///     `X8ConfigurationLoader`.
    ///   - environment: The environment visible to supported scalar
    ///     expansions. It is used as an isolated value map.
    /// - Returns: A validated configuration that is safe for a frontend to use
    ///   when constructing its selected backend.
    /// - Throws: `X8ConfigurationResolutionError` naming the offending key
    ///   path for unsupported versions, missing or invalid fields, invalid
    ///   read/write combinations, or unsupported scalar expansion syntax.
    package func resolve(
        _ document: X8ConfigurationDocument,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> X8Configuration {
        guard let version = document.version else {
            throw X8ConfigurationResolutionError.missingField("version")
        }
        guard version == 1 else {
            throw X8ConfigurationResolutionError.unsupportedVersion(version)
        }
        guard let s3 = document.s3 else {
            throw X8ConfigurationResolutionError.missingField("s3")
        }

        var expander = ScalarParameterExpander(environment: environment)
        var api: X8S3APIConfiguration?
        if let document = s3.api {
            api = try X8S3APIResolver.resolve(document, expander: &expander)
        }
        let read = try Self.resolveRead(s3.read, api: api, expander: &expander)
        let write = try Self.resolveWrite(s3.write, api: api)
        let socketPath = try Self.resolveSocketPath(document.socketPath, expander: &expander)

        guard read != .none || write != .none else {
            throw X8ConfigurationResolutionError.readAndWriteDisabled
        }
        let configuration = X8Configuration(version: version, read: read, write: write, socketPath: socketPath)
        guard api == nil || configuration.api != nil else {
            throw X8ConfigurationResolutionError.unusedAPI
        }
        return configuration
    }

    private static func resolveRead(
        _ document: X8AccessPathDocument?,
        api: X8S3APIConfiguration?,
        expander: inout ScalarParameterExpander
    ) throws -> X8ReadPath {
        switch document {
        case .token("api"):
            return try .api(require(api, for: "s3.read"))
        case .token("none"):
            return .none
        case let .map(publicURL?):
            let expanded = try expander.expand(publicURL)
            return try .publicURL(
                X8ConfigurationURLValidator.url(expanded, field: "s3.read.publicURL", requiresTrailingSlash: true)
            )
        case .map(nil):
            throw X8ConfigurationResolutionError.missingField("s3.read.publicURL")
        case .token:
            throw X8ConfigurationResolutionError.invalidField("s3.read", reason: "expected api, none, or publicURL: <url>")
        case nil:
            throw X8ConfigurationResolutionError.missingField("s3.read")
        }
    }

    private static func resolveWrite(
        _ document: X8AccessPathDocument?,
        api: X8S3APIConfiguration?
    ) throws -> X8WritePath {
        switch document {
        case .token("api"):
            try .api(require(api, for: "s3.write"))
        case .token("none"):
            .none
        case .token("publicURL"), .map:
            throw X8ConfigurationResolutionError.publicURLWrite
        case .token:
            throw X8ConfigurationResolutionError.invalidField("s3.write", reason: "expected api or none")
        case nil:
            throw X8ConfigurationResolutionError.missingField("s3.write")
        }
    }

    /// Expands `socketPath` and rejects a path unusable as a Unix domain socket endpoint.
    ///
    /// The kernel's `sockaddr_un.sun_path` on macOS is 104 bytes including the
    /// terminating NUL, so any path at or beyond 104 UTF-8 bytes cannot be
    /// bound at all; this is checked after `$VAR` expansion, since that is
    /// the length the kernel actually sees. A relative path would be resolved
    /// against whatever directory a command happens to run from instead of a
    /// fixed team-shared location, defeating the point of pinning it.
    private static func resolveSocketPath(
        _ value: String?,
        expander: inout ScalarParameterExpander
    ) throws -> String? {
        guard let value else { return nil }
        let socketPath = try expander.expand(value)
        guard !socketPath.isEmpty else { return nil }
        guard socketPath.hasPrefix("/"), socketPath.utf8.count < 104 else {
            throw X8ConfigurationResolutionError.invalidField(
                "socketPath",
                reason: "expected an absolute path shorter than 104 bytes"
            )
        }
        return socketPath
    }

    private static func require(_ api: X8S3APIConfiguration?, for field: String) throws -> X8S3APIConfiguration {
        guard let api else {
            throw X8ConfigurationResolutionError.apiRequired(field)
        }
        return api
    }
}
