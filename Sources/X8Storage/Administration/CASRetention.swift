import X8Core

/// A retention snapshot and whether it is safe to use for destructive GC.
///
/// `isAuthoritative` is a safety gate, not an indication that the list is
/// merely non-empty. A purge may traverse and delete unreachable CAS objects
/// only when the provider can prove that all roots and leases for this cache
/// domain were included in the snapshot.
public struct CASRetentionSnapshot: Sendable {
    /// The roots and leases observed for the cache domain.
    public let anchors: [CASRetentionAnchor]

    /// Whether the provider can assert that the snapshot is complete.
    public let isAuthoritative: Bool

    /// Creates a retention snapshot.
    public init(anchors: [CASRetentionAnchor], isAuthoritative: Bool) {
        self.anchors = anchors
        self.isAuthoritative = isAuthoritative
    }
}

/// Reads only reference-graph metadata without loading CAS payloads.
///
/// A missing object is returned as `nil` so purge can classify it as an unsafe
/// graph rather than silently treating a missing reference as unreachable.
public protocol CASReferenceReader: Sendable {
    /// Returns ordered references, or nil when the object is absent.
    func references(of id: CASDataID) async throws -> [CASDataID]?
}

/// Persists X8-owned roots and leases separately from opaque Action Cache values.
///
/// Retention data is an X8 administration concern. Implementations return a
/// complete snapshot with an authority flag and use revisions for conditional
/// anchor deletion, allowing CAS garbage collection to fail closed.
public protocol CASRetentionStore: Sendable {
    /// Reads a complete retention snapshot for one cache domain.
    func retentionSnapshot() async throws -> CASRetentionSnapshot

    /// Replaces or creates one root or lease.
    func putRetentionAnchor(_ anchor: CASRetentionAnchor) async throws

    /// Removes one root or lease at the expected revision.
    func deleteRetentionAnchor(_ anchor: CASRetentionAnchor) async throws -> CacheDeleteResult
}
