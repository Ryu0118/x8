import X8Core

/// Raised when a stored CAS record does not hash to the identifier it was read under.
///
/// The record is corrupt or was written by something other than X8, so its
/// bytes must not reach the compiler. This is a remote error, not a cache
/// miss: the client still falls back to building locally, but the condition
/// stays visible instead of looking like an empty cache.
package struct CASDataIntegrityError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The identifier whose stored record failed verification.
    package let id: CASDataID

    /// Creates an integrity error for the identifier that was read.
    package init(id: CASDataID) {
        self.id = id
    }

    /// A diagnostic that names the failing identifier in hex.
    package var description: String {
        let hex = id.rawValue.map { String(format: "%02x", $0) }.joined()
        return "CAS record \(hex) failed integrity verification: its payload and references do not match its identifier."
    }
}
