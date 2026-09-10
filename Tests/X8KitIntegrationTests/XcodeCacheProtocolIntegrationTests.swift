import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Testing
import X8Core
@testable import X8Kit
import X8Storage

@Suite("Xcode cache protocol over a Unix socket")
struct XcodeCacheProtocolIntegrationTests {
    @Test("serves all six RPCs and preserves wire payload choices")
    func servesAllRPCsOverUnixSocket() async throws {
        let fixture = try await UnixSocketServerFixture(storage: InMemoryStorage())
        let sourceURL = fixture.directory.appending(path: "input.bin")
        let sourceBytes = Data([0x01, 0x00, 0xFE, 0xFF])
        try sourceBytes.write(to: sourceURL)

        let result = try await fixture.withClient { cas, keyValue in
            let savedID = try await cas.save(saveRequest(filePath: sourceURL.path))
            let loaded = try await cas.load(loadRequest(for: savedID, writeToDisk: false))
            let loadedBytes = try inlineBytes(from: loaded)

            let reference = Data([0x10, 0x11])
            let putResponse = try await cas.put(
                putRequest(
                    bytes: Data([0x21, 0x22]),
                    references: [reference]
                )
            )
            let objectID = try responseID(from: putResponse)
            let inlineObject = try await cas.get(getRequest(for: objectID, writeToDisk: false))
            let diskObject = try await cas.get(getRequest(for: objectID, writeToDisk: true))
            let diskBytes = try fileBytes(from: diskObject)

            let actionKey = Data([0x31, 0x00, 0x32])
            let entries = [
                "result": Data([0x41, 0x42]),
                "metadata": Data([0x51, 0xFF]),
            ]
            _ = try await keyValue.putValue(putValueRequest(key: actionKey, entries: entries))
            let action = try await keyValue.getValue(getValueRequest(key: actionKey))

            return try ProtocolResult(
                loadedBytes: loadedBytes,
                inlineObject: inlineObjectValue(from: inlineObject),
                diskBytes: diskBytes.bytes,
                responseFilePath: diskBytes.path,
                actionEntries: actionValue(from: action)
            )
        }

        #expect(result.loadedBytes == sourceBytes)
        #expect(result.inlineObject.bytes == Data([0x21, 0x22]))
        #expect(result.inlineObject.references == [referenceBytes()])
        #expect(result.diskBytes == Data([0x21, 0x22]))
        #expect(FileManager.default.fileExists(atPath: result.responseFilePath) == false)
        #expect(result.actionEntries == [
            "result": Data([0x41, 0x42]),
            "metadata": Data([0x51, 0xFF]),
        ])
    }

    @Test("returns protocol misses and backend errors through the socket")
    func returnsMissesAndErrorsOverUnixSocket() async throws {
        let missingFixture = try await UnixSocketServerFixture(storage: InMemoryStorage())
        let missing = try await missingFixture.withClient { cas, keyValue in
            let missingID = wireID(Data([0x61]))
            let casResponse = try await cas.get(getRequest(for: missingID, writeToDisk: false))
            let actionResponse = try await keyValue.getValue(getValueRequest(key: Data([0x62])))
            return (casResponse.outcome, actionResponse.outcome)
        }

        #expect(missing.0 == .objectNotFound)
        #expect(missing.1 == .keyNotFound)

        let errorFixture = try await UnixSocketServerFixture(storage: FailingStorage())
        let errors = try await errorFixture.withClient { cas, keyValue in
            var getRequest = CompilationCacheService_Cas_V1_CASGetRequest()
            getRequest.casID = wireID(Data([0x71]))
            let casResponse = try await cas.get(getRequest)

            let actionResponse = try await keyValue.getValue(getValueRequest(key: Data([0x72])))
            return (casResponse, actionResponse)
        }

        #expect(errors.0.outcome == .error)
        #expect(errors.0.error.description_p == "backend failure")
        #expect(errors.1.outcome == .error)
        #expect(errors.1.error.description_p == "backend failure")
    }

    private struct ProtocolResult: Sendable {
        let loadedBytes: Data
        let inlineObject: InlineObject
        let diskBytes: Data
        let responseFilePath: String
        let actionEntries: [String: Data]
    }

    private struct InlineObject: Sendable {
        let bytes: Data
        let references: [Data]
    }

    private func saveRequest(filePath: String) -> CompilationCacheService_Cas_V1_CASSaveRequest {
        var request = CompilationCacheService_Cas_V1_CASSaveRequest()
        request.data.blob.contents = .filePath(filePath)
        return request
    }

    private func putRequest(
        bytes: Data,
        references: [Data]
    ) -> CompilationCacheService_Cas_V1_CASPutRequest {
        var request = CompilationCacheService_Cas_V1_CASPutRequest()
        request.data.blob.contents = .data(bytes)
        request.data.references = references.map(wireID)
        return request
    }

    private func getRequest(
        for id: CompilationCacheService_Cas_V1_CASDataID,
        writeToDisk: Bool
    ) -> CompilationCacheService_Cas_V1_CASGetRequest {
        var request = CompilationCacheService_Cas_V1_CASGetRequest()
        request.casID = id
        request.writeToDisk = writeToDisk
        return request
    }

    private func loadRequest(
        for response: CompilationCacheService_Cas_V1_CASSaveResponse,
        writeToDisk: Bool
    ) throws -> CompilationCacheService_Cas_V1_CASLoadRequest {
        let id = try responseID(from: response)
        return loadRequest(for: id, writeToDisk: writeToDisk)
    }

    private func loadRequest(
        for id: CompilationCacheService_Cas_V1_CASDataID,
        writeToDisk: Bool
    ) -> CompilationCacheService_Cas_V1_CASLoadRequest {
        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID = id
        request.writeToDisk = writeToDisk
        return request
    }

    private func putValueRequest(
        key: Data,
        entries: [String: Data]
    ) -> CompilationCacheService_Keyvalue_V1_PutValueRequest {
        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries = entries
        return request
    }

    private func getValueRequest(
        key: Data
    ) -> CompilationCacheService_Keyvalue_V1_GetValueRequest {
        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key
        return request
    }

    private func responseID(
        from response: CompilationCacheService_Cas_V1_CASSaveResponse
    ) throws -> CompilationCacheService_Cas_V1_CASDataID {
        guard case let .casID(id) = response.contents else {
            throw IntegrationTestError.unexpectedResponse("CAS Save did not return an ID.")
        }
        return id
    }

    private func responseID(
        from response: CompilationCacheService_Cas_V1_CASPutResponse
    ) throws -> CompilationCacheService_Cas_V1_CASDataID {
        guard case let .casID(id) = response.contents else {
            throw IntegrationTestError.unexpectedResponse("CAS Put did not return an ID.")
        }
        return id
    }

    private func inlineBytes(
        from response: CompilationCacheService_Cas_V1_CASLoadResponse
    ) throws -> Data {
        guard case let .data(blob) = response.contents,
              case let .data(bytes) = blob.blob.contents
        else {
            throw IntegrationTestError.unexpectedResponse("CAS Load did not return inline bytes.")
        }
        return bytes
    }

    private func fileBytes(
        from response: CompilationCacheService_Cas_V1_CASGetResponse
    ) throws -> (bytes: Data, path: String) {
        guard case let .data(object) = response.contents,
              case let .filePath(path) = object.blob.contents
        else {
            throw IntegrationTestError.unexpectedResponse("CAS Get did not return a response file.")
        }
        return try (Data(contentsOf: URL(filePath: path)), path)
    }

    private func inlineObjectValue(
        from response: CompilationCacheService_Cas_V1_CASGetResponse
    ) throws -> InlineObject {
        guard case let .data(object) = response.contents,
              case let .data(bytes) = object.blob.contents
        else {
            throw IntegrationTestError.unexpectedResponse("CAS Get did not return an inline object.")
        }
        return InlineObject(
            bytes: bytes,
            references: object.references.map(\.id)
        )
    }

    private func actionValue(
        from response: CompilationCacheService_Keyvalue_V1_GetValueResponse
    ) throws -> [String: Data] {
        guard case let .value(value) = response.contents else {
            throw IntegrationTestError.unexpectedResponse("GetValue did not return a value.")
        }
        return value.entries
    }

    private func wireID(_ bytes: Data) -> CompilationCacheService_Cas_V1_CASDataID {
        var id = CompilationCacheService_Cas_V1_CASDataID()
        id.id = bytes
        return id
    }

    private func referenceBytes() -> Data {
        Data([0x10, 0x11])
    }
}

private enum IntegrationTestError: Error, CustomStringConvertible, Sendable {
    case unexpectedResponse(String)

    var description: String {
        switch self {
        case let .unexpectedResponse(message):
            message
        }
    }
}

private struct FailingStorage: CASStore, ActionCacheStore, Sendable {
    func get(id _: CASDataID) async throws -> CASObject? {
        throw BackendFailure()
    }

    func put(_: CASObject) async throws -> CASDataID {
        throw BackendFailure()
    }

    func load(id _: CASDataID) async throws -> ByteStream? {
        throw BackendFailure()
    }

    func save(_: ByteStream) async throws -> CASDataID {
        throw BackendFailure()
    }

    func getValue(for _: ActionCacheKey) async throws -> ActionCacheValue? {
        throw BackendFailure()
    }

    func putValue(_: ActionCacheValue, for _: ActionCacheKey) async throws {
        throw BackendFailure()
    }
}

private struct BackendFailure: Error, CustomStringConvertible, Sendable {
    var description: String {
        "backend failure"
    }
}

private struct UnixSocketServerFixture<Storage: CASStore & ActionCacheStore & Sendable>: Sendable {
    let directory: URL
    private let runner: XcodeServeRunner

    init(storage: Storage) async throws {
        let directory = URL(filePath: "/private/tmp")
            .appending(path: "x8-protocol-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let socketPath = directory.appending(path: "cache.sock").path
        self.directory = directory
        runner = XcodeServeRunner(
            socketPath: socketPath,
            casStore: storage,
            actionCacheStore: storage
        )
    }

    func withClient<Result: Sendable>(
        _ operation: @escaping (
            CompilationCacheService_Cas_V1_CASDBService.Client<HTTP2ClientTransport.Posix>,
            CompilationCacheService_Keyvalue_V1_KeyValueDB.Client<HTTP2ClientTransport.Posix>
        ) async throws -> Result
    ) async throws -> Result {
        let handle = try await runner.start()
        do {
            let result = try await withGRPCClient(
                transport: HTTP2ClientTransport.Posix(
                    target: .unixDomainSocket(path: handle.socketPath),
                    transportSecurity: .plaintext
                )
            ) { client in
                try await operation(
                    .init(wrapping: client),
                    .init(wrapping: client)
                )
            }
            await handle.shutdown()
            try? FileManager.default.removeItem(at: directory)
            return result
        } catch {
            await handle.shutdown()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
