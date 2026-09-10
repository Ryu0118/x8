import X8Core

/// Errors raised when a content-addressed identifier conflicts with its data.
///
/// A storage backend may receive the same generated identifier again, but it
/// must reject a different payload or reference shape instead of overwriting
/// the existing immutable record.
public struct StorageError: Error, Equatable, Sendable {
    /// The kind of CAS data conflict.
    public enum Kind: Equatable, Sendable {
        /// The identifier was already associated with a different complete object.
        case conflictingCASObject

        /// The identifier was already associated with different blob bytes.
        case conflictingCASBlob
    }

    /// The kind of conflict.
    public let kind: Kind

    /// The identifier associated with the conflicting data.
    public let id: CASDataID

    /// Creates a CAS storage error.
    public init(kind: Kind, id: CASDataID) {
        self.kind = kind
        self.id = id
    }
}
