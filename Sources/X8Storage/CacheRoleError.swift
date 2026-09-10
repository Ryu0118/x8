/// The error thrown when a cache-role restriction rejects a write attempt.
///
/// This is separate from `StorageError`, which always carries a
/// `CASDataID` for a content conflict. A role rejection has no CAS
/// identifier in the Action Cache case, so it needs its own error shape.
public struct CacheRoleError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The invocation's cache role does not permit this write.
    public static let writeNotAllowed = CacheRoleError()

    /// A human-readable explanation of the rejection.
    public var description: String {
        "This invocation's cache role does not permit writing to the cache."
    }
}
