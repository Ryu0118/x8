import Foundation

/// A provider observation used to inspect or conditionally delete one object.
///
/// `CacheObject` is not the object's payload. It is a snapshot of the
/// provider-specific key, cache namespace, opaque identifier, optional age and
/// size metadata, and the revision required to make a deletion safe.
public struct CacheObject: Hashable, Sendable {
    /// The provider-specific key used to delete this object.
    public let key: String

    /// The cache namespace containing the object.
    public let kind: CacheObjectKind

    /// The identifier encoded by the object key.
    public let identifier: Data

    /// The last successful write time, when the provider supplied one.
    public let modifiedAt: Date?

    /// The object size, when the provider supplied one.
    public let byteCount: Int64?

    /// The revision required for a safe conditional delete.
    public let revision: StorageRevision?

    /// Creates cache-object metadata.
    public init(
        key: String,
        kind: CacheObjectKind,
        identifier: Data,
        modifiedAt: Date?,
        byteCount: Int64?,
        revision: StorageRevision?
    ) {
        self.key = key
        self.kind = kind
        self.identifier = identifier
        self.modifiedAt = modifiedAt
        self.byteCount = byteCount
        self.revision = revision
    }
}
