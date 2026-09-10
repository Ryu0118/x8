import X8Core
import X8Storage

/// Decodes an Action Cache value's CAS roots for reachability-based purge.
///
/// Xcode's Action Cache value carries its result as a
/// `CompilationCacheService_Cas_V1_CASObject` message under the `"value"`
/// entry (verified against a real cache bucket); its `references` are the
/// CAS objects that value's build produced, plus a trailing reference to a
/// schema-kind marker object. This extractor treats every reference as an
/// opaque root without interpreting the object it points to further, per
/// this repository's rule to treat Xcode CAS identifiers as opaque.
package struct ActionCacheRootExtractor: Sendable {
    /// Creates an extractor.
    package init() {}

    /// Returns the CAS roots referenced by one Action Cache value.
    ///
    /// - Returns: `nil` when the `"value"` entry is missing or does not parse
    ///   as a `CASObject`; the caller must treat that as an unrecognized
    ///   value, not as zero roots, since a mismatched schema means this
    ///   extractor needs a code fix, not a purge decision.
    package func roots(in value: ActionCacheValue) -> [CASDataID]? {
        guard let bytes = value.entries["value"] else { return nil }
        guard let object = try? CompilationCacheService_Cas_V1_CASObject(serializedBytes: bytes) else {
            return nil
        }
        return object.references.map { CASDataID(rawValue: $0.id) }
    }
}
