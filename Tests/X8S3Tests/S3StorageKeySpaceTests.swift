#if X8_S3
    import Foundation
    import Testing
    import X8Core
    @testable import X8S3
    import X8Storage

    @Suite("S3 object keys stay within one configured category")
    struct S3StorageKeySpaceTests {
        @Test
        func derivesAllObjectCategories() {
            let keySpace = S3StorageKeySpace()
            let identifier = Data([0x0A, 0xFF])

            let casKey = keySpace.cas(id: identifier)
            let actionCacheKey = keySpace.actionCache(key: identifier)
            let stagingKey = keySpace.staging(identifier: identifier)
            let retentionKey = keySpace.retention(identifier: identifier)

            #expect(casKey == "cas/0aff")
            #expect(actionCacheKey == "action-cache/0aff")
            #expect(stagingKey == "staging/0aff")
            #expect(retentionKey == "retention/0aff")
            #expect(keySpace.authorityMarkerKey == "retention/.authoritative")
        }

        @Test
        func acceptsOnlyKeysInsideTheConfiguredCategory() {
            let keySpace = S3StorageKeySpace()
            let identifier = Data([0x0A, 0xFF])
            let object = CacheObject(
                key: keySpace.cas(id: identifier),
                kind: .cas,
                identifier: identifier,
                modifiedAt: nil,
                byteCount: nil,
                revision: nil
            )

            let parsedIdentifier = keySpace.identifier(from: object.key, for: .cas)
            let matches = keySpace.matches(object)
            let foreignIdentifier = keySpace.identifier(
                from: "action-cache/0aff",
                for: .cas
            )

            #expect(parsedIdentifier == identifier)
            #expect(matches)
            #expect(foreignIdentifier == nil)
        }

        @Test
        func hexEncodesEveryByteValueWithZeroPadding() {
            let keySpace = S3StorageKeySpace()
            let identifier = Data([0x00, 0x01, 0x9F, 0xFF])

            #expect(keySpace.cas(id: identifier) == "cas/00019fff")
        }
    }
#endif
