import X8Core

/// Errors raised when a purge cannot be performed safely.
public enum CachePurgeError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The supplied age or grace period is negative.
    case negativeDuration

    /// A CAS grace period was not supplied.
    case missingGracePeriod

    /// CAS retention support was not supplied.
    case retentionStoreUnavailable

    /// CAS reference traversal support was not supplied.
    case referenceReaderUnavailable

    /// An Action Cache store was not supplied for deriving CAS purge roots.
    case actionCacheStoreUnavailable

    /// The provider could not prove that its root snapshot was complete.
    case nonAuthoritativeRetention

    /// An Action Cache value had no entry the injected root extractor could parse.
    case unrecognizedActionCacheValue(ActionCacheKey)

    /// A root or reference was missing during traversal.
    case missingReferencedObject(CASDataID)

    /// The reference graph exceeded the safety bound.
    case graphLimitExceeded

    /// A destructive operation was requested without explicit confirmation.
    case confirmationRequired

    /// A diagnostic description suitable for CLI output.
    public var description: String {
        switch self {
        case .negativeDuration:
            "Purge durations must not be negative."
        case .missingGracePeriod:
            "CAS purge requires an explicit grace period."
        case .retentionStoreUnavailable:
            "CAS purge requires an authoritative retention store."
        case .referenceReaderUnavailable:
            "CAS purge requires a CAS reference reader."
        case .actionCacheStoreUnavailable:
            "CAS purge requires an Action Cache store to derive live roots."
        case .nonAuthoritativeRetention:
            "CAS purge refused because retention roots are not authoritative."
        case let .unrecognizedActionCacheValue(key):
            "CAS purge refused because an Action Cache value has no parseable CAS object reference: \(String(describing: key.rawValue)). The value layout may have changed."
        case let .missingReferencedObject(id):
            "CAS purge found a missing referenced object: \(String(describing: id.rawValue))."
        case .graphLimitExceeded:
            "CAS purge refused because the reference graph exceeded the safety limit."
        case .confirmationRequired:
            "Destructive purge requires explicit confirmation."
        }
    }
}
