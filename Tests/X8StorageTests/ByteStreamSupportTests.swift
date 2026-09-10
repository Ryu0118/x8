import Foundation
import Testing
@testable import X8Storage

@Suite("Byte stream file boundaries")
struct ByteStreamSupportTests {
    @Test
    func fileStreamReadsInRequestedChunks() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "x8-byte-stream-" + UUID().uuidString)
        let bytes = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let stream = try ByteStreamSupport.make(
            fileAt: url,
            fileManager: FileManager.default,
            chunkSize: 2
        )
        var chunks: [Data] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        #expect(chunks == [Data([0x01, 0x02]), Data([0x03, 0x04]), Data([0x05])])
    }

    @Test
    func collectRejectsBytesOverTheLimit() async {
        let stream = ByteStreamSupport.make(Data([0x01, 0x02]))

        await #expect(throws: ByteStreamSupport.Error.exceededMaximumBytes) {
            try await ByteStreamSupport.collect(stream, maximumBytes: 1)
        }
    }

    @Test
    func collectPrefixReturnsFullDataWithoutExceedingWhenUnderLimit() async throws {
        let stream = ByteStreamSupport.make(Data([0x01, 0x02]))

        let result = try await ByteStreamSupport.collectPrefix(stream, maximumBytes: 4)

        #expect(result.prefix == Data([0x01, 0x02]))
        #expect(result.exceededLimit == false)
        var remainderBytes = Data()
        for try await chunk in result.remainder {
            remainderBytes.append(contentsOf: chunk)
        }
        #expect(remainderBytes.isEmpty)
    }

    @Test
    func collectPrefixSplitsAtTheLimitAndPreservesTheRemainderAsAStream() async throws {
        let chunks = stride(from: 1, through: 5, by: 1).map {
            Data(repeating: UInt8($0), count: 2)
        }
        let source = ChunkSource(chunks: chunks)
        let stream = ByteStreamSupport.make { await source.next() }

        let result = try await ByteStreamSupport.collectPrefix(stream, maximumBytes: 5)

        #expect(result.prefix.count == 5)
        #expect(result.exceededLimit == true)
        let fullData = try await ByteStreamSupport.collect(
            ByteStreamSupport.prepend(result.prefix, to: result.remainder)
        )
        #expect(fullData == chunks.reduce(Data(), +))
    }

    @Test
    func fileStreamUsesInjectedFileManagerForReadability() {
        let fileManager = UnreadableFileManager()

        #expect(throws: CocoaError.self) {
            _ = try ByteStreamSupport.make(
                fileAt: URL(filePath: "/private/tmp/unreadable-cache-input"),
                fileManager: fileManager
            )
        }
    }

    @Test
    func writeReturnsByteCountAndPreservesContent() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "x8-byte-stream-write-" + UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try FileHandle(forWritingTo: url)
        let byteCount = try await ByteStreamSupport.write(
            ByteStreamSupport.make(Data([0x11, 0x12, 0x13])),
            to: file
        )
        try file.close()

        #expect(byteCount == 3)
        #expect(try Data(contentsOf: url) == Data([0x11, 0x12, 0x13]))
    }
}

private final class UnreadableFileManager: FileManager, @unchecked Sendable {
    override func isReadableFile(atPath _: String) -> Bool {
        false
    }
}

private actor ChunkSource {
    private var chunks: [Data]
    private var index = 0

    init(chunks: [Data]) {
        self.chunks = chunks
    }

    func next() -> Data? {
        guard index < chunks.count else { return nil }
        defer { index += 1 }
        return chunks[index]
    }
}
