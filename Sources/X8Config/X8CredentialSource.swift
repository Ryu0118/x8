/// Where signed S3 API access obtains its credentials.
package enum X8CredentialSource: Equatable, Sendable {
    /// Credentials written in the configuration, usually via `${VAR}` references.
    case `static`(RemoteCacheCredentials)

    /// Soto's default provider chain: environment, shared config, SSO, and instance metadata.
    case defaultChain

    /// The static credentials, or `nil` when the default chain resolves them.
    package var staticCredentials: RemoteCacheCredentials? {
        guard case let .static(credentials) = self else { return nil }
        return credentials
    }
}
