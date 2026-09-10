#if X8_S3
    import Foundation
    import Testing
    import X8Core
    @testable import X8S3

    @Suite("S3 storage envelopes reject malformed input")
    struct S3StorageCodecTests {
        @Test
        func roundTripPreservesEmptyAndReferencedCASRecords() throws {
            let record = S3CASRecord(
                bytes: Data([0x01, 0x02]),
                references: [
                    CASDataID(rawValue: Data([0xA0])),
                    CASDataID(rawValue: Data([0xB0, 0xB1])),
                ]
            )

            let decoded = try S3StorageCodec.decodeCAS(S3StorageCodec.encodeCAS(record))

            #expect(decoded.bytes == record.bytes)
            #expect(decoded.references == record.references)
        }

        @Test
        func truncatedCASRecordReturnsDecodeError() {
            let data = Data([0x58, 0x38, 0x43, 0x41, 0x53, 0x01, 0x00])

            #expect(throws: S3StorageCodecError.invalidCASRecord) {
                _ = try S3StorageCodec.decodeCAS(data)
            }
        }

        @Test
        func oversizedCASReferenceCountReturnsDecodeError() {
            var data = Data([0x58, 0x38, 0x43, 0x41, 0x53, 0x01])
            data.append(contentsOf: encodedCount(UInt64.max))

            #expect(throws: S3StorageCodecError.invalidCASRecord) {
                _ = try S3StorageCodec.decodeCAS(data)
            }
        }

        @Test
        func actionCacheEncodingIsStable() {
            let first = ActionCacheValue(entries: [
                "z": Data([0x01]),
                "a": Data([0x02]),
            ])
            let second = ActionCacheValue(entries: [
                "a": Data([0x02]),
                "z": Data([0x01]),
            ])

            #expect(S3StorageCodec.encodeActionCache(first) == S3StorageCodec.encodeActionCache(second))
        }

        @Test
        func invalidUTF8ActionCacheKeyReturnsDecodeError() {
            var malformed = Data([0x58, 0x38, 0x4B, 0x56, 0x01])
            malformed.append(contentsOf: encodedCount(1))
            malformed.append(contentsOf: encodedCount(1))
            malformed.append(0xFF)
            malformed.append(contentsOf: encodedCount(0))

            #expect(throws: S3StorageCodecError.invalidActionCacheValue) {
                _ = try S3StorageCodec.decodeActionCache(malformed)
            }
        }

        @Test
        func trailingActionCacheBytesReturnDecodeError() {
            var data = S3StorageCodec.encodeActionCache(ActionCacheValue(entries: [:]))
            data.append(0x00)

            #expect(throws: S3StorageCodecError.invalidActionCacheValue) {
                _ = try S3StorageCodec.decodeActionCache(data)
            }
        }

        private func encodedCount(_ value: UInt64) -> Data {
            var value = value.bigEndian
            return withUnsafeBytes(of: &value) { Data($0) }
        }
    }
#endif
