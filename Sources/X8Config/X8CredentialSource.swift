/// Where signed S3 API access obtains its credentials.
package enum X8CredentialSource: Equatable, Sendable {
    /// Credentials written in the configuration, usually via `${VAR}` references.
    case `static`(RemoteCacheCredentials)

    /// Soto's default provider chain: environment, shared config, SSO, and instance metadata.
    case defaultChain
}
