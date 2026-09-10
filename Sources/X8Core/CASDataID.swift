import Foundation

/// An opaque binary identifier for one item in Xcode's Content-Addressed Storage (CAS).
///
/// Xcode supplies this identifier to CAS `Load` or `Get` after receiving it
/// from a CAS `Save` or `Put` response. Preserve its exact bytes; it is not an
/// Action Cache key, project identifier, S3 key, or identifier recalculated by
/// X8. A backend-generated response identifier is opaque to Xcode as well and
/// is used only through the CAS protocol boundary.
public struct CASDataID: Hashable, Sendable {
    /// The exact bytes supplied by the cache protocol.
    public let rawValue: Data

    /// Creates an identifier without interpreting or transforming its bytes.
    public init(rawValue: Data) {
        self.rawValue = rawValue
    }
}
