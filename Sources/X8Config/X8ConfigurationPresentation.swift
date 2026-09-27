/// Renders resolved configuration without exposing credential values or runtime state.
package enum X8ConfigurationPresentation {
    /// Returns the human-readable output used by `x8 config show`.
    ///
    /// The output describes the selected read and write paths, the storage
    /// profile, and the credential source. It intentionally contains no
    /// socket path because configuration loading does not start a proxy or
    /// establish a runtime endpoint.
    package static func render(_ configuration: X8Configuration) -> String {
        fields(configuration).map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    /// Returns ordered, non-secret fields for frontends that own their renderer.
    package static func fields(_ configuration: X8Configuration) -> [(key: String, value: String)] {
        let read = switch configuration.read {
        case .api: "api"
        case let .publicURL(url): "publicURL \(url.absoluteString)"
        case .none: "none"
        }
        let write = configuration.write == .none ? "none" : "api"
        let api: [(key: String, value: String)] = configuration.api.map {
            [
                ("endpoint", $0.endpoint?.absoluteString ?? "<default>"),
                ("region", $0.region),
                ("bucket", $0.bucket),
            ]
        } ?? []

        return [("version", String(configuration.version)), ("read", read), ("write", write)]
            + api
            + [("profile_id", configuration.profileID), ("credentials", credentialSource(configuration))]
    }

    /// Returns the non-secret description of how credentials are resolved.
    package static func credentialSource(_ configuration: X8Configuration) -> String {
        switch configuration.api?.credentials {
        case .static: "static (redacted)"
        case .defaultChain: "default-chain"
        case nil: "none (no s3.api)"
        }
    }
}
