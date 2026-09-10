import X8Core

/// A complete CAS record returned by `CASDBService.Get` or accepted by `Put`.
///
/// The bytes are the record's payload, and each reference identifies another
/// CAS record in the ordered object graph. A blob-only record has no
/// references. The payload remains a `ByteStream` so adapters do not have to
/// buffer an entire object merely to pass it between protocol and storage.
public struct CASObject: Sendable {
    /// The object's byte content.
    public let bytes: ByteStream

    /// The references in the order defined by the cache protocol.
    public let references: [CASDataID]

    /// Creates a CAS object from its byte stream and references.
    public init(bytes: ByteStream, references: [CASDataID]) {
        self.bytes = bytes
        self.references = references
    }
}
