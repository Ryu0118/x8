#if X8_S3
    import Foundation
    import X8Core
    import X8Storage

    /// The decoded payload and references stored in one S3 CAS object.
    ///
    /// This is the codec's buffered representation. The storage path uses the
    /// header-only decoder when it needs to preserve the payload as a stream.
    package struct S3CASRecord: Sendable {
        /// The object's payload bytes.
        package let bytes: Data

        /// The object's ordered CAS references.
        package let references: [CASDataID]

        /// Creates a decoded CAS record.
        package init(bytes: Data, references: [CASDataID]) {
            self.bytes = bytes
            self.references = references
        }
    }

    /// Errors raised while decoding X8's S3 envelopes.
    ///
    /// Malformed headers, counts, and version bytes are rejected before a
    /// decoded record is exposed to the storage actor.
    package enum S3StorageCodecError: Error, Equatable, Sendable {
        /// The CAS envelope is malformed.
        case invalidCASRecord

        /// The action-cache envelope is malformed.
        case invalidActionCacheValue
    }

    /// Encodes and decodes X8's versioned S3 object envelopes.
    ///
    /// CAS objects use a bounded header containing ordered opaque references,
    /// followed by the payload bytes. Action Cache values use a separate
    /// versioned envelope. Header decoding deliberately returns the untouched
    /// remainder as a stream; complete decoding is reserved for bounded data.
    package enum S3StorageCodec {
        static let casHeader = Data([0x58, 0x38, 0x43, 0x41, 0x53, 0x01])
        static let actionCacheHeader = Data([0x58, 0x38, 0x4B, 0x56, 0x01])

        private static let maximumReferenceCount = 1_000_000
        private static let maximumReferenceLength = 1024 * 1024
        private static let maximumCASHeaderBytes = 64 * 1024 * 1024

        /// The initial ranged-read size a caller should request when it only
        /// needs a CAS object's header (magic, reference count, and
        /// references), not its payload. Most real objects' references fit
        /// well within this bound; a header that does not must be re-read in
        /// full, which the caller detects from a truncated stream.
        package static let recommendedHeaderReadBytes: Int64 = 64 * 1024

        // Provider bytes are untrusted; bound counts and header growth before
        // reserving arrays or iterating over attacker-controlled metadata.

        /// Encodes a CAS record.
        package static func encodeCAS(_ record: S3CASRecord) -> Data {
            var data = encodeCASHeader(references: record.references)
            data.append(contentsOf: record.bytes)
            return data
        }

        /// Encodes the CAS envelope prefix so a payload can remain a stream.
        package static func encodeCASHeader(references: [CASDataID]) -> Data {
            var data = casHeader
            BigEndianUInt64.append(UInt64(references.count), to: &data)
            for reference in references {
                BigEndianUInt64.append(UInt64(reference.rawValue.count), to: &data)
                data.append(contentsOf: reference.rawValue)
            }
            return data
        }

        /// Decodes the CAS envelope prefix and returns the untouched payload stream.
        package static func decodeCASHeader(
            from stream: ByteStream
        ) async throws -> (references: [CASDataID], bytes: ByteStream) {
            var reader = StreamReader(stream: stream)
            try await reader.expect(casHeader, error: .invalidCASRecord)
            let referenceCount = try await reader.readCount(
                error: .invalidCASRecord,
                maximum: maximumReferenceCount
            )
            var references: [CASDataID] = []
            references.reserveCapacity(referenceCount)
            var headerBytes = casHeader.count + MemoryLayout<UInt64>.size

            for _ in 0 ..< referenceCount {
                let length = try await reader.readCount(
                    error: .invalidCASRecord,
                    maximum: maximumReferenceLength
                )
                try validateHeaderBytes(
                    &headerBytes,
                    adding: MemoryLayout<UInt64>.size + length
                )
                let rawValue = try await reader.readBytes(
                    count: length,
                    error: .invalidCASRecord
                )
                references.append(CASDataID(rawValue: rawValue))
            }

            // The reader may have consumed part of a provider chunk; its remainder owns those bytes.
            return (references, reader.remainder())
        }

        /// Decodes a complete CAS record from buffered data.
        package static func decodeCAS(_ data: Data) throws -> S3CASRecord {
            var reader = Reader(data: data)
            try reader.expect(casHeader, error: .invalidCASRecord)
            let referenceCount = try reader.readCount(
                error: .invalidCASRecord,
                minimumBytesPerItem: MemoryLayout<UInt64>.size,
                maximum: maximumReferenceCount
            )
            var references: [CASDataID] = []
            references.reserveCapacity(referenceCount)

            for _ in 0 ..< referenceCount {
                let referenceLength = try reader.readCount(
                    error: .invalidCASRecord,
                    maximum: maximumReferenceLength
                )
                try references.append(
                    CASDataID(
                        rawValue: reader.readBytes(
                            count: referenceLength,
                            error: .invalidCASRecord
                        )
                    )
                )
            }

            return S3CASRecord(bytes: reader.readRemainingBytes(), references: references)
        }

        private static func validateHeaderBytes(
            _ current: inout Int,
            adding bytes: Int
        ) throws {
            let (next, overflow) = current.addingReportingOverflow(bytes)
            guard !overflow, next <= maximumCASHeaderBytes else {
                throw S3StorageCodecError.invalidCASRecord
            }
            current = next
        }
    }
#endif
