import Foundation
import Testing
import X8Core
import X8Storage

@Suite("In-memory CAS storage")
struct InMemoryCASTests {
    @Test
    func missingObjectAndBlobReturnNil() async throws {
        let storage = InMemoryStorage()
        let identifier = CASDataID(rawValue: Data([0xAA]))

        let object = try await storage.get(id: identifier)
        let blob = try await storage.load(id: identifier)

        #expect(object == nil)
        #expect(blob == nil)
    }

    @Test
    func putAndGetPreserveObjectContentAndReferences() async throws {
        let storage = InMemoryStorage()
        let chunks = [Data([0x01, 0x02]), Data([0x03])]
        let references = [
            CASDataID(rawValue: Data([0x10])),
            CASDataID(rawValue: Data([0x20, 0x21])),
        ]

        let identifier = try await storage.put(
            ByteStreamTestSupport.makeObject(
                chunks: chunks,
                references: references
            )
        )
        let object = try #require(try await storage.get(id: identifier))
        let content = try await ByteStreamTestSupport.collect(object.bytes)

        #expect(content == Data([0x01, 0x02, 0x03]))
        #expect(object.references == references)
    }

    @Test
    func saveAndLoadReturnBlobBytesAndEmptyReferences() async throws {
        let storage = InMemoryStorage()
        let chunks = [Data([0x04]), Data([0x05, 0x06])]

        let identifier = try await storage.save(
            ByteStreamTestSupport.makeStream(from: chunks)
        )
        let stream = try #require(try await storage.load(id: identifier))
        let content = try await ByteStreamTestSupport.collect(stream)
        let object = try #require(try await storage.get(id: identifier))

        #expect(content == Data([0x04, 0x05, 0x06]))
        #expect(object.references.isEmpty)
    }

    @Test
    func putObjectCanBeLoadedAsPayload() async throws {
        let storage = InMemoryStorage()
        let references = [CASDataID(rawValue: Data([0x31]))]

        let identifier = try await storage.put(
            ByteStreamTestSupport.makeObject(
                chunks: [Data([0x32, 0x33])],
                references: references
            )
        )
        let stream = try #require(try await storage.load(id: identifier))

        #expect(try await ByteStreamTestSupport.collect(stream) == Data([0x32, 0x33]))
    }

    @Test
    func identicalObjectWritesAreIdempotent() async throws {
        let storage = InMemoryStorage()
        let chunks = [Data([0x07, 0x08])]
        let references = [CASDataID(rawValue: Data([0x30]))]

        let firstObjectID = try await storage.put(
            ByteStreamTestSupport.makeObject(
                chunks: chunks,
                references: references
            )
        )
        let secondObjectID = try await storage.put(
            ByteStreamTestSupport.makeObject(
                chunks: chunks,
                references: references
            )
        )

        #expect(firstObjectID == secondObjectID)
    }

    @Test
    func identicalBlobWritesAreIdempotent() async throws {
        let storage = InMemoryStorage()
        let chunks = [Data([0x07, 0x08])]

        let firstBlobID = try await storage.save(
            ByteStreamTestSupport.makeStream(from: chunks)
        )
        let secondBlobID = try await storage.save(
            ByteStreamTestSupport.makeStream(from: chunks)
        )

        #expect(firstBlobID == secondBlobID)
    }

    @Test
    func streamAndDataIdentifiersMatchAcrossChunkBoundaries() async throws {
        let bytes = Data([0x11, 0x12, 0x13])
        let references = [CASDataID(rawValue: Data([0x21]))]
        let dataID = CASDataIDGenerator.id(for: bytes, references: references)
        let streamID = try await CASDataIDGenerator.id(
            for: ByteStreamTestSupport.makeStream(from: [Data([0x11]), Data([0x12, 0x13])]),
            references: references
        )

        #expect(streamID == dataID)
    }

    @Test
    func cancelledSaveDoesNotCommitPartialBlob() async throws {
        let storage = InMemoryStorage()
        let chunks = [Data([0x40]), Data([0x41])]
        let expectedID = try await InMemoryStorage().save(
            ByteStreamTestSupport.makeStream(from: chunks)
        )
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(
            of: Data.self
        )
        defer { continuation.finish() }
        continuation.yield(chunks[0])

        let saveTask = Task {
            try await storage.save(ByteStream(stream))
        }
        await Task.yield()
        saveTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await saveTask.value
        }
        #expect(try await storage.load(id: expectedID) == nil)
    }
}
