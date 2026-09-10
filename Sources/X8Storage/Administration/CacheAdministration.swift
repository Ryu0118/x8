import Foundation
import X8Core

/// Identifies one independently managed cache namespace.
///
/// The cases correspond to different cleanup rules: staging is temporary
/// upload state, Action Cache is mutable action-result metadata, and CAS is an
/// immutable object graph.
public enum CacheObjectKind: String, CaseIterable, Sendable {
    /// An incomplete or quarantined upload.
    case staging

    /// A mutable action-to-result record.
    case actionCache

    /// An immutable CAS object.
    case cas
}

/// Identifies one observed version of a remotely managed cache object.
///
/// The value is opaque to the storage layer. A caller carries it from a list
/// operation into a conditional delete so a purge cannot delete a replacement
/// written after the object was inspected.
public struct StorageRevision: Hashable, Sendable {
    /// The provider-specific revision bytes.
    public let rawValue: Data

    /// Creates a storage revision from provider-specific bytes.
    public init(rawValue: Data) {
        self.rawValue = rawValue
    }
}

/// Describes the result of a conditional cache-object deletion.
public enum CacheDeleteResult: Equatable, Sendable {
    /// The object was deleted at the expected revision.
    case deleted

    /// The object was already absent.
    case notFound

    /// The object changed after it was listed and was not deleted.
    case revisionChanged
}

/// One object a batch delete could not remove, with an opaque provider reason.
public struct CacheDeleteFailure: Hashable, Sendable {
    /// The provider key of the object that failed to delete.
    public let key: String

    /// An opaque provider-reported reason, kept for diagnostics only.
    public let reason: String

    /// Creates a batch-delete failure.
    public init(key: String, reason: String) {
        self.key = key
        self.reason = reason
    }
}

/// The outcome of deleting many objects in one call.
///
/// `skippedCount` covers objects a provider reports absent or changed, the
/// same safe outcomes `CacheDeleteResult` distinguishes for a single delete.
/// `failures` covers everything else: opaque provider errors a caller cannot
/// treat as a safe non-deletion.
public struct CacheBatchDeleteResult: Sendable {
    /// The number of objects deleted.
    public let deletedCount: Int

    /// The number of objects skipped as absent or changed.
    public let skippedCount: Int

    /// The objects a provider reported as failed, with an opaque reason.
    public let failures: [CacheDeleteFailure]

    /// Creates a batch-delete result.
    public init(deletedCount: Int, skippedCount: Int, failures: [CacheDeleteFailure]) {
        self.deletedCount = deletedCount
        self.skippedCount = skippedCount
        self.failures = failures
    }
}

/// Lists and conditionally deletes objects without exposing a provider SDK.
///
/// `listObjects(of:)` returns an observation containing provider key, identity,
/// age, size, and revision metadata. `delete(_:)` must compare that observed
/// revision at the provider and report `revisionChanged` instead of deleting
/// a newer object. The protocol is intentionally separate from CAS reads and
/// writes because it serves administrative tooling rather than Xcode RPCs.
public protocol CacheAdministration: Sendable {
    /// Lists the current metadata for one cache namespace.
    func listObjects(of kind: CacheObjectKind) async throws -> [CacheObject]

    /// Deletes an object only when its supplied revision still matches.
    ///
    /// - Returns: Whether the object was deleted, already absent, or changed
    ///   since the observation was created.
    func delete(_ object: CacheObject) async throws -> CacheDeleteResult

    /// Deletes many objects in provider-sized batches.
    ///
    /// Implementations verify each object's revision where the provider can
    /// enforce it per key; where it cannot, the caller's fresh listing is the
    /// only revision check, so callers must re-list immediately before
    /// calling this.
    func delete(_ objects: [CacheObject]) async throws -> CacheBatchDeleteResult
}
