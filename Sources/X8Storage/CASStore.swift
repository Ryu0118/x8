import X8Core

/// Stores the complete-object and blob-only views of one CAS namespace.
///
/// `get(id:)` and `load(id:)` distinguish a missing record with `nil` from a
/// provider failure thrown by the backend. `put(_:)` preserves an object's
/// ordered references, while `save(_:)` stores a blob with no references. The
/// returned `CASDataID` is opaque to this protocol's callers; implementations
/// may derive it from the payload, allocate it, or map it to a provider key as
/// long as the protocol's returned identifier can be used for subsequent reads.
public protocol CASStore: Sendable {
    /// Returns a record with payload and ordered references, or `nil` when missing.
    func get(id: CASDataID) async throws -> CASObject?

    /// Stores a complete object and returns its opaque identifier.
    func put(_ object: CASObject) async throws -> CASDataID

    /// Returns payload bytes for a record, or `nil` when the identifier is missing.
    func load(id: CASDataID) async throws -> ByteStream?

    /// Stores blob bytes and returns their opaque identifier.
    func save(_ bytes: ByteStream) async throws -> CASDataID
}
