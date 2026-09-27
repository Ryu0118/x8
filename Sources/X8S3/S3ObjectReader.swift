#if X8_S3
    import X8Storage

    /// Reads whole cache objects on the Xcode request path.
    ///
    /// `nil` is a cache miss. Any condition that cannot be proven to be a miss,
    /// including a permission failure, must be thrown so the caller can keep
    /// misses distinct from remote errors.
    package protocol S3ObjectReader: Sendable {
        /// Returns an object's bytes, or `nil` when the object is absent.
        func get(key: String, kind: CacheObjectKind) async throws -> ByteStream?
    }
#endif
