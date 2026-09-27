import CryptoKit
import Foundation
import X8Storage

/// The resolved, non-runtime configuration for one remote-cache profile.
///
/// The resolver guarantees that `api` is present exactly when `read` or
/// `write` is `.api`; both paths then share that one value. The value holds
/// no client or filesystem state. `profileID` identifies the non-secret cache domain and is
/// safe to use for stable local runtime paths.
package struct X8Configuration: Equatable, Sendable {
    /// The configuration schema version.
    package let version: Int

    /// The signed S3 API access shared by any path set to `.api`.
    package let api: X8S3APIConfiguration?

    /// How this invocation reads the cache.
    package let read: X8ReadPath

    /// How this invocation writes the cache.
    package let write: X8WritePath

    /// The optional fixed Unix socket path for the cache proxy.
    ///
    /// `nil` unless `.x8.yml` set `socketPath`, in which case commands that
    /// otherwise derive a per-user path from `profileID` use this path
    /// instead. Excluded from `canonicalProfile`: it names where the socket
    /// lives, not the cache domain it serves.
    package let socketPath: String?

    /// Creates a configuration value without performing validation.
    package init(
        version: Int = 1,
        api: X8S3APIConfiguration? = nil,
        read: X8ReadPath,
        write: X8WritePath,
        socketPath: String? = nil
    ) {
        self.version = version
        self.api = api
        self.read = read
        self.write = write
        self.socketPath = socketPath
    }

    /// The storage-boundary permissions implied by the read and write paths.
    package var role: CacheRole {
        var role: CacheRole = []
        if read != .none {
            role.insert(.consumer)
        }
        if write != .none {
            role.insert(.producer)
        }
        return role
    }

    /// A stable identifier for the non-secret profile and cache domain.
    package var profileID: String {
        let digest = SHA256.hash(data: Data(canonicalProfile.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private var canonicalProfile: String {
        // The cache domain is the bucket when API access exists, otherwise the public URL.
        // Access paths and credentials are excluded so a reader and a writer of one bucket
        // share runtime paths. Length-prefixing prevents concatenation collisions; the
        // format tag invalidates local identities if cache-key semantics change.
        let domain: [String] = if let api {
            ["api", api.endpoint?.absoluteString ?? "", api.region, api.bucket]
        } else {
            ["public", read.publicURL?.absoluteString ?? ""]
        }
        return ([String(version)] + domain + ["x8-cas-v2"])
            .map { "\($0.utf8.count):\($0)" }
            .joined()
    }
}
