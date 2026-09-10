import Foundation

/// Resolves a raw configuration document into a validated runtime-neutral profile.
///
/// This is the in-memory stage after loading. It applies the schema version,
/// environment expansion, defaults, credential construction, and path and
/// endpoint validation, then returns `X8Configuration`. It performs no file or
/// network I/O and never selects or constructs a storage provider. The supplied
/// environment is copied into an isolated expansion context, so assignment
/// expressions cannot mutate the caller's process environment.
public struct X8ConfigurationResolver: Sendable {
    /// Creates a configuration resolver.
    public init() {}

    /// Expands, validates, and resolves a raw configuration document.
    ///
    /// - Parameters:
    ///   - document: The optional raw values decoded by
    ///     `X8ConfigurationLoader`.
    ///   - environment: The environment visible to supported scalar
    ///     expansions. It is used as an isolated value map.
    /// - Returns: A validated configuration that is safe for a frontend to use
    ///   when constructing its selected backend.
    /// - Throws: `X8ConfigurationResolutionError` for unsupported versions,
    ///   missing or invalid fields, incomplete credentials, or unsupported
    ///   scalar expansion syntax.
    public func resolve(
        _ document: X8ConfigurationDocument,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> X8Configuration {
        guard let version = document.version else {
            throw X8ConfigurationResolutionError.missingField("version")
        }
        guard version == 1 else {
            throw X8ConfigurationResolutionError.unsupportedVersion(version)
        }

        var expander = ScalarParameterExpander(environment: environment)
        let values = try Self.expand(
            document,
            version: version,
            expander: &expander
        )
        try Self.validate(values)

        return X8Configuration(
            version: values.version,
            bucket: values.bucket,
            region: values.region,
            endpoint: values.endpoint,
            role: values.role,
            credentials: values.credentials
        )
    }

    private struct ExpandedValues {
        let version: Int
        let bucket: String
        let region: String
        let endpoint: URL?
        let role: CacheRole
        let credentials: RemoteCacheCredentials?
    }

    private static func expand(
        _ document: X8ConfigurationDocument,
        version: Int,
        expander: inout ScalarParameterExpander
    ) throws -> ExpandedValues {
        // Resolve the required storage identity before optional provider settings.
        let bucket = try expandRequiredValue(
            document.bucket,
            field: "bucket",
            expander: &expander
        )
        let region = try expander.expand(document.region ?? "us-east-1")
        let role = document.role ?? .both

        // Endpoint and credentials use the same isolated expansion environment.
        let endpoint = try resolveEndpoint(document.endpoint, expander: &expander)
        let credentials = try resolveCredentials(
            accessKeyID: document.accessKeyID,
            secretAccessKey: document.secretAccessKey,
            sessionToken: document.sessionToken,
            expander: &expander
        )

        return ExpandedValues(
            version: version,
            bucket: bucket,
            region: region,
            endpoint: endpoint,
            role: role,
            credentials: credentials
        )
    }

    private static func validate(_ values: ExpandedValues) throws {
        // Validate the expanded values, not the raw YAML strings.
        guard !values.region.isEmpty else {
            throw X8ConfigurationResolutionError.invalidField("region")
        }
        try validatePathComponent(values.bucket, field: "bucket")
    }

    private static func expandRequiredValue(
        _ value: String?,
        field: String,
        expander: inout ScalarParameterExpander
    ) throws -> String {
        guard let value else {
            throw X8ConfigurationResolutionError.missingField(field)
        }
        let expanded = try expander.expand(value)
        guard !expanded.isEmpty else {
            throw X8ConfigurationResolutionError.invalidField(field)
        }
        return expanded
    }

    private static func resolveEndpoint(
        _ value: String?,
        expander: inout ScalarParameterExpander
    ) throws -> URL? {
        guard let value else { return nil }
        let expanded = try expander.expand(value)
        // Reject credentials and URL modifiers so endpoint text cannot smuggle signing or secret data.
        guard let endpoint = URL(string: expanded),
              let scheme = endpoint.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              endpoint.host != nil,
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.query == nil,
              endpoint.fragment == nil
        else {
            throw X8ConfigurationResolutionError.invalidField("endpoint")
        }
        // Remote endpoints must use TLS; plain HTTP is limited to loopback development services.
        guard scheme == "https" || Self.isLocalEndpoint(endpoint) else {
            throw X8ConfigurationResolutionError.invalidField("endpoint")
        }
        return endpoint
    }

    private static func isLocalEndpoint(_ endpoint: URL) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(endpoint.host?.lowercased())
    }

    private static func resolveCredentials(
        accessKeyID: String?,
        secretAccessKey: String?,
        sessionToken: String?,
        expander: inout ScalarParameterExpander
    ) throws -> RemoteCacheCredentials? {
        // Any explicit credential field opts into static credentials; require the key pair instead of mixing providers.
        guard accessKeyID != nil || secretAccessKey != nil || sessionToken != nil else {
            return nil
        }
        guard let accessKeyID, let secretAccessKey else {
            throw X8ConfigurationResolutionError.incompleteCredentials
        }
        let accessKey = try expander.expand(accessKeyID)
        let secretKey = try expander.expand(secretAccessKey)
        guard !accessKey.isEmpty, !secretKey.isEmpty else {
            throw X8ConfigurationResolutionError.invalidField("credentials")
        }
        let token = try sessionToken.map { try expander.expand($0) }
        return RemoteCacheCredentials(
            accessKeyID: accessKey,
            secretAccessKey: secretKey,
            sessionToken: token?.isEmpty == true ? nil : token
        )
    }

    private static func validatePathComponent(_ value: String, field: String) throws {
        // Path separators and dot components would escape the configured object key.
        guard !value.contains("/"), !value.contains("\\"), value != ".", value != ".." else {
            throw X8ConfigurationResolutionError.invalidField(field)
        }
    }
}
