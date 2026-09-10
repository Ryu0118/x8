#if X8_S3
    import Foundation
    import X8Core
    import X8Storage

    /// Errors raised while decoding an X8 retention document.
    ///
    /// Retention documents are X8-owned administrative metadata and are not
    /// Action Cache values or CAS payloads.
    package enum S3RetentionCodecError: Error, Equatable, Sendable {
        /// The document is not a supported X8 retention record.
        case invalidDocument
    }

    /// Encodes X8-owned roots and leases independently of Action Cache values.
    ///
    /// The authority marker is written only when the retention namespace is
    /// explicitly managed by X8. A valid-looking document without that marker
    /// is not enough to authorize destructive CAS garbage collection.
    package enum S3RetentionCodec {
        /// A marker proving that the retention namespace was explicitly enabled.
        package static let authorityMarker = Data("X8-RETENTION-AUTHORITY-V1".utf8)

        private static let currentVersion = 1

        /// Encodes a retention anchor using the platform's standard Codable JSON format.
        package static func encode(_ anchor: CASRetentionAnchor) throws -> Data {
            try JSONEncoder().encode(
                Document(
                    version: currentVersion,
                    kind: anchor.kind.rawValue,
                    identifier: anchor.identifier,
                    objectIDs: anchor.objectIDs.map(\.rawValue),
                    expiresAt: anchor.expiresAt
                )
            )
        }

        /// Decodes a retention anchor and attaches the provider revision observed beside it.
        package static func decode(
            _ data: Data,
            revision: StorageRevision?
        ) throws -> CASRetentionAnchor {
            let document: Document
            do {
                document = try JSONDecoder().decode(Document.self, from: data)
            } catch {
                throw S3RetentionCodecError.invalidDocument
            }
            guard document.version == currentVersion,
                  let kind = CASRetentionAnchor.Kind(rawValue: document.kind)
            else {
                throw S3RetentionCodecError.invalidDocument
            }
            return CASRetentionAnchor(
                kind: kind,
                identifier: document.identifier,
                objectIDs: document.objectIDs.map(CASDataID.init(rawValue:)),
                expiresAt: document.expiresAt,
                revision: revision
            )
        }

        private struct Document: Codable {
            let version: Int
            let kind: String
            let identifier: Data
            let objectIDs: [Data]
            let expiresAt: Date?
        }
    }
#endif
