#if X8_S3
    import AsyncOperations
    import Foundation
    import Testing
    import X8Core
    @testable import X8S3
    import X8Storage

    @Suite("S3 backend preserves remote CAS and action-cache semantics")
    struct S3StorageTests {
        @Test
        func storesCASObjectUnderExpectedKey() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let references = [CASDataID(rawValue: Data([0x01, 0x02]))]
            let object = CASObject(
                bytes: TestByteStream.make([Data([0x03, 0x04])]),
                references: references
            )

            let id = try await storage.put(object)
            let stored = try #require(await client.value(for: "cas/\(id.rawValue.hexString)"))
            let loaded = try S3StorageCodec.decodeCAS(stored)

            #expect(loaded.bytes == Data([0x03, 0x04]))
            #expect(loaded.references == references)
        }

        @Test
        func retriesIdenticalCASWritesAtTheSameKey() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let object = CASObject(
                bytes: TestByteStream.make([Data([0x01, 0x02])]),
                references: []
            )

            let firstID = try await storage.put(object)
            let secondID = try await storage.put(
                CASObject(
                    bytes: TestByteStream.make([Data([0x01]), Data([0x02])]),
                    references: []
                )
            )

            #expect(secondID == firstID)
            #expect(await client.objectCount == 1)
            #expect(await client.putCallCount == 1)
        }

        @Test
        func coalescesConcurrentPutsOfTheSameCASObject() async throws {
            let client = FakeS3ObjectClient()
            let gate = Gate()
            await client.gatePuts(on: gate)
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let bytes = Data([0x01, 0x02, 0x03])

            let opener = Task {
                try? await Task.sleep(nanoseconds: 20_000_000)
                await gate.open()
            }
            let results = try await Array(repeating: bytes, count: 10).asyncMap(
                numberOfConcurrentTasks: 10
            ) { bytes in
                try await storage.put(
                    CASObject(bytes: TestByteStream.make([bytes]), references: [])
                )
            }
            await opener.value

            #expect(Set(results).count == 1)
            #expect(await client.putCallCount == 1)
        }

        @Test
        func repeatedActionCachePutsWithTheSameValueAreDeduplicated() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let key = ActionCacheKey(rawValue: Data([0x01]))
            let value = ActionCacheValue(entries: ["result": Data([0x02])])

            try await storage.putValue(value, for: key)
            try await storage.putValue(value, for: key)

            #expect(await client.putCallCount == 1)
        }

        @Test
        func actionCachePutsWithDifferentValuesForTheSameKeyBothRun() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let key = ActionCacheKey(rawValue: Data([0x01]))

            try await storage.putValue(ActionCacheValue(entries: ["result": Data([0x02])]), for: key)
            try await storage.putValue(ActionCacheValue(entries: ["result": Data([0x03])]), for: key)

            #expect(await client.putCallCount == 2)
        }

        @Test
        func readsStreamedCASHeaderAndPayload() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let references = [CASDataID(rawValue: Data([0xBB, 0xBC]))]
            let id = CASDataIDGenerator.id(for: Data([0x01, 0x02, 0x03]), references: references)
            let envelope = S3StorageCodec.encodeCAS(
                S3CASRecord(bytes: Data([0x01, 0x02, 0x03]), references: references)
            )
            await client.seed(
                [
                    Data(envelope.prefix(4)),
                    Data(envelope.dropFirst(4).prefix(9)),
                    Data(envelope.dropFirst(13)),
                ],
                for: "cas/\(id.rawValue.hexString)"
            )

            let object = try #require(await storage.get(id: id))
            let bytes = try await TestByteStream.collect(object.bytes)
            let blob = try #require(await storage.load(id: id))

            #expect(object.references == references)
            #expect(bytes == Data([0x01, 0x02, 0x03]))
            #expect(try await TestByteStream.collect(blob) == Data([0x01, 0x02, 0x03]))
        }

        @Test
        func rejectsATamperedCASPayloadForEveryReadPath() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let id = try await storage.put(
                CASObject(bytes: TestByteStream.make([Data([0x01, 0x02])]), references: [])
            )
            let tampered = S3StorageCodec.encodeCAS(S3CASRecord(bytes: Data([0x01, 0xFF]), references: []))
            await client.seed([tampered], for: "cas/\(id.rawValue.hexString)")

            let object = try #require(await storage.get(id: id))
            await #expect(throws: CASDataIntegrityError(id: id)) {
                _ = try await TestByteStream.collect(object.bytes)
            }
            let blob = try #require(await storage.load(id: id))
            await #expect(throws: CASDataIntegrityError(id: id)) {
                _ = try await TestByteStream.collect(blob)
            }
        }

        @Test
        func rejectsTamperedCASReferences() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let references = [CASDataID(rawValue: Data([0x01]))]
            let id = try await storage.put(
                CASObject(bytes: TestByteStream.make([Data([0x02])]), references: references)
            )
            let tampered = S3StorageCodec.encodeCAS(
                S3CASRecord(bytes: Data([0x02]), references: [CASDataID(rawValue: Data([0x09]))])
            )
            await client.seed([tampered], for: "cas/\(id.rawValue.hexString)")

            let object = try #require(await storage.get(id: id))

            await #expect(throws: CASDataIntegrityError(id: id)) {
                _ = try await TestByteStream.collect(object.bytes)
            }
        }

        @Test
        func referencesReadsOnlyAHeaderSizedRange() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let id = CASDataID(rawValue: Data([0xCC]))
            let references = [CASDataID(rawValue: Data([0xDD]))]
            let envelope = S3StorageCodec.encodeCAS(
                S3CASRecord(bytes: Data(repeating: 0x7A, count: 4096), references: references)
            )
            await client.seed([envelope], for: "cas/\(id.rawValue.hexString)")

            let result = try await storage.references(of: id)

            #expect(result == references)
            let ranges = await client.requestedByteRanges
            #expect(ranges.count == 1)
            let range = try #require(ranges.first ?? nil)
            #expect(range.upperBound - range.lowerBound + 1 == S3StorageCodec.recommendedHeaderReadBytes)
        }

        @Test
        func referencesFallsBackToAFullReadWhenTheRangedReadIsExhausted() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let id = CASDataID(rawValue: Data([0xEE]))
            let referenceCount = Int(S3StorageCodec.recommendedHeaderReadBytes / 8) + 10
            let references = (0 ..< referenceCount).map { CASDataID(rawValue: Data([UInt8($0 % 256)])) }
            let envelope = S3StorageCodec.encodeCAS(
                S3CASRecord(bytes: Data([0x01]), references: references)
            )
            await client.seed([envelope], for: "cas/\(id.rawValue.hexString)")

            let result = try await storage.references(of: id)

            #expect(result == references)
            let ranges = await client.requestedByteRanges
            #expect(ranges.count == 2)
            #expect(ranges[1] == nil)
        }

        @Test
        func referencesFallsBackToAFullReadWhenTheProviderIgnoresTheByteRange() async throws {
            let client = FakeS3ObjectClient()
            await client.setIgnoresByteRange(true)
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let id = CASDataID(rawValue: Data([0xFF]))
            // Large enough that the whole object (returned in place of the
            // requested range) still exceeds recommendedHeaderReadBytes.
            let referenceCount = Int(S3StorageCodec.recommendedHeaderReadBytes / 8) + 10
            let references = (0 ..< referenceCount).map { CASDataID(rawValue: Data([UInt8($0 % 256)])) }
            let envelope = S3StorageCodec.encodeCAS(
                S3CASRecord(bytes: Data([0x01]), references: references)
            )
            await client.seed([envelope], for: "cas/\(id.rawValue.hexString)")

            let result = try await storage.references(of: id)

            #expect(result == references)
            let ranges = await client.requestedByteRanges
            #expect(ranges.count == 2)
            #expect(ranges[1] == nil)
        }

        @Test
        func preservesActionCacheEntries() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let key = ActionCacheKey(rawValue: Data([0xAA, 0x00]))
            let value = ActionCacheValue(entries: [
                "value": Data([0x01, 0xFF]),
                "metadata": Data([0x02]),
            ])

            try await storage.putValue(value, for: key)
            let loaded = try #require(try await storage.getValue(for: key))

            #expect(loaded == value)
        }

        @Test
        func missingRecordsReturnNil() async throws {
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: FakeS3ObjectClient()
            )

            let object = try await storage.get(id: CASDataID(rawValue: Data([0x01])))
            let value = try await storage.getValue(for: ActionCacheKey(rawValue: Data([0x02])))

            #expect(object == nil)
            #expect(value == nil)
        }

        @Test
        func listsObjectsAndRejectsStaleConditionalDeletes() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let key = "cas/aa"
            await client.seed(
                [Data([0x01])],
                for: key,
                modifiedAt: Date(timeIntervalSince1970: 0)
            )

            let listed = try await storage.listObjects(of: .cas)
            let object = try #require(listed.first)
            #expect(object.identifier == Data([0xAA]))
            #expect(object.byteCount == 1)

            await client.seed([Data([0x02])], for: key)
            #expect(try await storage.delete(object) == .revisionChanged)

            let current = try #require(try await storage.listObjects(of: .cas).first)
            #expect(try await storage.delete(current) == .deleted)
        }

        @Test
        func preservesAnEmptyOpaqueActionKeyInTheObjectNamespace() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            try await storage.putValue(
                ActionCacheValue(entries: ["value": Data([0x01])]),
                for: ActionCacheKey(rawValue: Data())
            )

            let object = try #require(
                try await storage.listObjects(of: .actionCache).first
            )
            #expect(object.identifier.isEmpty)
            #expect(try await storage.delete(object) == .deleted)
        }

        @Test
        func emptyRetentionNamespaceIsAuthoritativeWithoutAMarker() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )

            let snapshot = try await storage.retentionSnapshot()

            #expect(snapshot.anchors.isEmpty)
            #expect(snapshot.isAuthoritative)
        }

        @Test
        func anchorsWithoutTheAuthorityMarkerAreNotAuthoritative() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let anchor = CASRetentionAnchor(
                kind: .root,
                identifier: Data([0x40]),
                objectIDs: [CASDataID(rawValue: Data([0x41]))],
                expiresAt: nil,
                revision: nil
            )
            let encoded = try S3RetentionCodec.encode(anchor)
            await client.seed([encoded], for: "retention/\(anchor.identifier.hexString)")

            let snapshot = try await storage.retentionSnapshot()

            #expect(snapshot.anchors.count == 1)
            #expect(snapshot.isAuthoritative == false)
        }

        @Test
        func retentionAnchorsRoundTripWithAuthorityMarker() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            let root = CASDataID(rawValue: Data([0x10]))
            let anchor = CASRetentionAnchor(
                kind: .root,
                identifier: Data([0x20]),
                objectIDs: [root],
                expiresAt: nil,
                revision: nil
            )

            try await storage.putRetentionAnchor(anchor)
            let snapshot = try await storage.retentionSnapshot()
            let stored = try #require(snapshot.anchors.first)

            #expect(snapshot.isAuthoritative)
            #expect(stored.kind == anchor.kind)
            #expect(stored.identifier == anchor.identifier)
            #expect(stored.objectIDs == anchor.objectIDs)
            #expect(stored.revision != nil)
            #expect(try await storage.deleteRetentionAnchor(stored) == .deleted)
        }

        @Test
        func refusesCASPurgeAuthorityWhenRetentionRecordIsMalformed() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            await client.seed(
                [S3RetentionCodec.authorityMarker],
                for: "retention/.authoritative"
            )
            await client.seed(
                [Data("not-json".utf8)],
                for: "retention/zz"
            )

            let snapshot = try await storage.retentionSnapshot()

            #expect(snapshot.anchors.isEmpty)
            #expect(snapshot.isAuthoritative == false)
        }

        @Test
        func retentionSnapshotReadsManyAnchorsConcurrentlyWithoutLosingAny() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            var anchors: [CASRetentionAnchor] = []
            for index in 0 ..< 80 {
                let byte = UInt8(index)
                let objectID = CASDataID(rawValue: Data([byte]))
                let anchor = CASRetentionAnchor(
                    kind: .root,
                    identifier: Data([byte, 0xAA]),
                    objectIDs: [objectID],
                    expiresAt: nil,
                    revision: nil
                )
                anchors.append(anchor)
            }
            for anchor in anchors {
                try await storage.putRetentionAnchor(anchor)
            }

            let snapshot = try await storage.retentionSnapshot()
            let expectedIdentifiers = Set(anchors.map(\.identifier))
            let actualIdentifiers = Set(snapshot.anchors.map(\.identifier))

            #expect(snapshot.isAuthoritative)
            #expect(snapshot.anchors.count == anchors.count)
            #expect(actualIdentifiers == expectedIdentifiers)
        }

        @Test
        func batchDeleteChunksToTheProviderKeyLimit() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            for index in 0 ..< 2300 {
                let identifier = String(format: "%06x", index)
                await client.seed([Data([0x01])], for: "cas/\(identifier)")
            }
            let objects = try await storage.listObjects(of: .cas)
            #expect(objects.count == 2300)

            let result = try await storage.delete(objects)

            #expect(result.deletedCount == 2300)
            #expect(result.failures.isEmpty)
            #expect(await client.deleteObjectsRequestSizes.sorted() == [300, 1000, 1000])
        }

        @Test
        func batchDeleteMapsProviderOutcomesToTheirCategories() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(bucket: "foo"),
                objectClient: client
            )
            await client.seed([Data([0x01])], for: "cas/aa")
            let listed = try await storage.listObjects(of: .cas)
            let present = try #require(listed.first { $0.key == "cas/aa" })
            let missing = CacheObject(
                key: "cas/ff",
                kind: .cas,
                identifier: Data([0xFF]),
                modifiedAt: Date(),
                byteCount: 1,
                revision: StorageRevision(rawValue: Data("some-revision".utf8))
            )
            await client.setIgnoresBatchPreconditions(false)
            await client.seed([Data([0x02])], for: "cas/aa")

            let result = try await storage.delete([present, missing])

            #expect(result.failures.map(\.key) == ["cas/aa"])
            #expect(result.deletedCount == 1)
        }
    }

#endif
