import Foundation
import X8Core

/// Identifies a durable root or expiring lease used by CAS garbage collection.
///
/// The anchor owns reachability roots, not payload ownership. Its `objectIDs`
/// are traversed through `CASReferenceReader`; `expiresAt` controls whether a
/// lease is active at a purge's chosen time, and `revision` protects updates
/// made after the retention snapshot was read.
public struct CASRetentionAnchor: Hashable, Sendable {
    /// The anchor kind.
    public enum Kind: String, Sendable {
        /// A durable root that remains until explicitly replaced or removed.
        case root

        /// An expiring root held by a short-lived publisher or consumer.
        case lease
    }

    /// The anchor kind.
    public let kind: Kind

    /// The provider-specific anchor identifier.
    public let identifier: Data

    /// The CAS objects kept reachable by this anchor.
    public let objectIDs: [CASDataID]

    /// The expiry time, or nil for a durable root.
    public let expiresAt: Date?

    /// The revision required for a conditional anchor update.
    public let revision: StorageRevision?

    /// Creates a retention anchor.
    public init(
        kind: Kind,
        identifier: Data,
        objectIDs: [CASDataID],
        expiresAt: Date?,
        revision: StorageRevision?
    ) {
        self.kind = kind
        self.identifier = identifier
        self.objectIDs = objectIDs
        self.expiresAt = expiresAt
        self.revision = revision
    }
}
