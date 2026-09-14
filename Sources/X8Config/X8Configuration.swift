import CryptoKit
import Foundation
import X8Storage

/// The resolved, non-runtime configuration for one remote-cache profile.
///
/// This value contains the official executable's S3-shaped profile and optional
/// credentials, but no client or filesystem state. The executable uses it to
/// construct S3 storage. `profileID` identifies the non-secret cache domain and
/// is safe to use for stable local runtime paths.
package struct X8Configuration: Equatable, Sendable {
    /// The configuration schema version.
    package let version: Int

    /// The object-store bucket containing the cache domain.
    package let bucket: String

    /// The object-store signing region.
    package let region: String

    /// The optional S3-compatible endpoint.
    package let endpoint: URL?

    /// Whether this invocation may push, pull, or both.
    ///
    /// This gates storage-boundary reads and writes, not cache identity, so it
    /// is intentionally excluded from `canonicalProfile`: a producer and a
    /// consumer invocation of the same repository configuration must resolve
    /// to the same profile and object-key space.
    package let role: CacheRole

    /// The optional literal credentials resolved from configuration.
    package let credentials: RemoteCacheCredentials?

    /// Creates a remote-cache configuration value without performing validation.
    package init(
        version: Int = 1,
        bucket: String,
        region: String = "us-east-1",
        endpoint: URL? = nil,
        role: CacheRole = .both,
        credentials: RemoteCacheCredentials? = nil
    ) {
        self.version = version
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        self.role = role
        self.credentials = credentials
    }

    /// A stable identifier for the non-secret profile and cache domain.
    package var profileID: String {
        let digest = SHA256.hash(data: Data(canonicalProfile.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private var canonicalProfile: String {
        // Length-prefix fields prevent concatenation collisions; the format tag
        // invalidates local identities if cache-key semantics change. Credentials
        // are intentionally excluded because the profile ID is non-secret.
        [
            String(version),
            endpoint?.absoluteString ?? "",
            region,
            bucket,
            "x8-cas-v1",
        ].map { "\($0.utf8.count):\($0)" }.joined()
    }
}
