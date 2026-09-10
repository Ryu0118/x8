import CryptoKit
import Foundation
import X8Core

/// Generates opaque identifiers for records created by a storage backend.
///
/// This is an implementation detail of storage backends, not Xcode's
/// identifier algorithm. Identifiers received from Xcode are never passed to
/// this generator or transformed by it. The generated value covers both the
/// payload and ordered references so a complete CAS object and a blob-only
/// record cannot accidentally share an identifier.
package enum CASDataIDGenerator {
    /// Creates an identifier for a payload and its ordered references.
    package static func id(
        for bytes: Data,
        references: [CASDataID] = []
    ) -> CASDataID {
        var hasher = SHA256()
        hasher.update(data: Data("X8-CAS-v1".utf8))
        hasher.update(data: bytes)
        updateHasher(&hasher, with: references)
        return CASDataID(rawValue: Data(hasher.finalize()))
    }

    /// Creates the same identifier while consuming a lazy payload stream.
    package static func id(
        for stream: ByteStream,
        references: [CASDataID] = []
    ) async throws -> CASDataID {
        var hasher = SHA256()
        hasher.update(data: Data("X8-CAS-v1".utf8))

        for try await chunk in stream {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }

        updateHasher(&hasher, with: references)
        return CASDataID(rawValue: Data(hasher.finalize()))
    }

    private static func updateHasher(
        _ hasher: inout SHA256,
        with references: [CASDataID]
    ) {
        updateHasher(&hasher, with: UInt64(references.count))
        for reference in references {
            updateHasher(&hasher, with: UInt64(reference.rawValue.count))
            hasher.update(data: reference.rawValue)
        }
    }

    private static func updateHasher(_ hasher: inout SHA256, with value: UInt64) {
        var data = Data()
        BigEndianUInt64.append(value, to: &data)
        hasher.update(data: data)
    }
}
