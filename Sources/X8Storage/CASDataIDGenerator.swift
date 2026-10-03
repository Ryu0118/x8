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
        var hasher = makeHasher()
        hasher.update(data: bytes)
        return finalize(&hasher, references: references)
    }

    /// Creates the same identifier while consuming a lazy payload stream.
    package static func id(
        for stream: ByteStream,
        references: [CASDataID] = []
    ) async throws -> CASDataID {
        var hasher = makeHasher()

        for try await chunk in stream {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }

        return finalize(&hasher, references: references)
    }

    /// Returns a lazy stream that forwards `stream` while re-deriving its identifier.
    ///
    /// Chunks are passed through unchanged as they are hashed, so the payload
    /// is never buffered. When the source completes, the stream throws
    /// `CASDataIntegrityError` instead of finishing if the payload and
    /// `references` do not produce `expected`. A consumer must therefore read
    /// to the end before it treats the bytes as a cache hit.
    package static func verifying(
        _ stream: ByteStream,
        references: [CASDataID],
        expected: CASDataID
    ) -> ByteStream {
        ByteStream {
            var iterator = stream.makeAsyncIterator()
            var hasher = makeHasher()
            var finished = false
            return ByteStream.AsyncIterator {
                guard !finished else { return nil }
                if let chunk = try await iterator.next() {
                    hasher.update(data: chunk)
                    return chunk
                }

                finished = true
                guard finalize(&hasher, references: references) == expected else {
                    throw CASDataIntegrityError(id: expected)
                }
                return nil
            }
        }
    }

    private static func makeHasher() -> SHA256 {
        var hasher = SHA256()
        hasher.update(data: Data("X8-CAS-v1".utf8))
        return hasher
    }

    private static func finalize(
        _ hasher: inout SHA256,
        references: [CASDataID]
    ) -> CASDataID {
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
