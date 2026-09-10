#if X8_S3
    import CryptoKit
    import Foundation
    import X8Core
    import X8Storage

    /// Identifies one Action Cache put by key and value content.
    ///
    /// `ActionCacheKey` alone is not content-addressed, so memoizing by key
    /// only would silently drop a later put that changes the value for the
    /// same key. Hashing the value's stable encoding (`S3StorageCodec`
    /// already sorts entries for deterministic bytes) lets a same-key,
    /// same-value put be safely skipped while a same-key, different-value
    /// put still runs.
    package struct ActionCacheDedupeKey: Hashable, Sendable {
        /// The Action Cache key this dedupe key wraps.
        package let key: ActionCacheKey
        private let valueDigest: SHA256Digest

        /// Creates a dedupe key from an Action Cache key and its value.
        package init(key: ActionCacheKey, value: ActionCacheValue) {
            self.key = key
            valueDigest = SHA256.hash(data: S3StorageCodec.encodeActionCache(value))
        }

        /// Combines the key and value digest into the given hasher.
        package func hash(into hasher: inout Hasher) {
            hasher.combine(key)
            hasher.combine(Data(valueDigest))
        }
    }
#endif
