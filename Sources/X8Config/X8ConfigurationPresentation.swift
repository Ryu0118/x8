/// Renders resolved configuration without exposing credential values or runtime state.
public enum X8ConfigurationPresentation {
    /// Returns the human-readable output used by `x8 config show`.
    ///
    /// The output describes the selected storage profile and credential source.
    /// It intentionally contains no socket path because configuration loading
    /// does not start a proxy or establish a runtime endpoint.
    public static func render(_ configuration: X8Configuration) -> String {
        fields(configuration).map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    /// Returns ordered, non-secret fields for frontends that own their renderer.
    public static func fields(_ configuration: X8Configuration) -> [(key: String, value: String)] {
        [
            ("version", String(configuration.version)),
            ("endpoint", configuration.endpoint?.absoluteString ?? "<default>"),
            ("region", configuration.region),
            ("bucket", configuration.bucket),
            ("role", configuration.role.configurationName ?? "unsupported (\(configuration.role.rawValue))"),
            ("profile_id", configuration.profileID),
            ("credentials", credentialSource(configuration)),
        ]
    }

    /// Returns the non-secret description of how credentials were resolved.
    public static func credentialSource(_ configuration: X8Configuration) -> String {
        configuration.credentials == nil ? "default-provider" : "static (redacted)"
    }
}
