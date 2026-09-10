import FileManagerProtocol
import Foundation
import Testing
@testable import X8Kit
import X8Storage

@Suite("Xcode cache wire keeps oversized hits distinct from remote errors")
struct XcodeCacheWireTests {
    @Test
    func bytesSpillsToResponseFileStoreWhenInlineBoundIsExceededEvenWithoutWriteToDiskRequested() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-wire-spill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responseFileStore = XcodeCacheResponseFileStore(directory: directory)
        let wire = XcodeCacheWire(
            responseFileStore: responseFileStore,
            fileManager: FileManager.default
        )
        let oversizedStream = ByteStreamSupport.make(
            Data(repeating: 0x42, count: XcodeCacheWire.maximumInlineResponseBytes + 1)
        )

        let result = try await wire.bytes(from: oversizedStream, writeToDisk: false)

        guard case let .filePath(path) = result.contents else {
            Issue.record("Expected an oversized hit to spill to a response file, not surface as an error.")
            return
        }
        let written = try Data(contentsOf: URL(filePath: path))
        #expect(written.count == XcodeCacheWire.maximumInlineResponseBytes + 1)
    }

    @Test
    func bytesThrowsInvalidRequestWhenInlineBoundIsExceededAndNoResponseFileStoreExists() async {
        let wire = XcodeCacheWire(responseFileStore: nil, fileManager: FileManager.default)
        let oversizedStream = ByteStreamSupport.make(
            Data(repeating: 0x42, count: XcodeCacheWire.maximumInlineResponseBytes + 1)
        )

        await #expect(throws: XcodeCacheServiceError.self) {
            _ = try await wire.bytes(from: oversizedStream, writeToDisk: false)
        }
    }

    @Test
    func bytesReturnsInlineDataWhenUnderTheBound() async throws {
        let wire = XcodeCacheWire(responseFileStore: nil, fileManager: FileManager.default)
        let stream = ByteStreamSupport.make(Data([0x01, 0x02, 0x03]))

        let result = try await wire.bytes(from: stream, writeToDisk: false)

        #expect(result.contents == .data(Data([0x01, 0x02, 0x03])))
    }
}
