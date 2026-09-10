import Foundation
import GRPCCore
import Testing
import X8Core
@testable import X8Kit
import X8Storage

@Suite("Xcode cache service maps CAS and action-cache messages")
struct XcodeCacheServiceTests {
    @Test
    func putAndGetPreserveObjectPayloadAndReferences() async throws {
        let storage = InMemoryStorage()
        let service = XcodeCacheCASService(casStore: storage)
        let references = [CASDataID(rawValue: Data([0x11, 0x12]))]
        var object = CompilationCacheService_Cas_V1_CASObject()
        object.blob = makeBytes(Data([0x21, 0x22]))
        object.references = references.map(makeWireID)
        var putRequest = CompilationCacheService_Cas_V1_CASPutRequest()
        putRequest.data = object

        let putResponse = try await service.put(request: putRequest, context: testContext())
        let wireID = try #require(putResponse.contents)
        guard case let .casID(storedID) = wireID else {
            Issue.record("CAS Put did not return a CAS ID.")
            return
        }
        var getRequest = CompilationCacheService_Cas_V1_CASGetRequest()
        getRequest.casID = storedID
        let getResponse = try await service.get(request: getRequest, context: testContext())

        #expect(getResponse.outcome == .success)
        guard case let .data(returnedObject) = getResponse.contents else {
            Issue.record("CAS Get did not return an object.")
            return
        }
        guard case let .data(returnedBytes) = returnedObject.blob.contents else {
            Issue.record("CAS Get did not return inline bytes.")
            return
        }
        #expect(returnedBytes == Data([0x21, 0x22]))
        #expect(returnedObject.references.map(\.id) == references.map(\.rawValue))
    }

    @Test
    func saveAcceptsFilePathAndLoadReturnsBlob() async throws {
        let storage = InMemoryStorage()
        let service = XcodeCacheCASService(casStore: storage)
        let path = "/private/tmp/x8-cache-service-\(UUID().uuidString).bin"
        let bytes = Data([0x31, 0x32, 0x33])
        try bytes.write(to: URL(filePath: path))
        defer { try? FileManager.default.removeItem(at: URL(filePath: path)) }
        var request = CompilationCacheService_Cas_V1_CASSaveRequest()
        request.data.blob = makeBytes(filePath: path)

        let saveResponse = try await service.save(request: request, context: testContext())

        guard case let .casID(storedID) = saveResponse.contents else {
            Issue.record("CAS Save did not return a CAS ID.")
            return
        }
        var loadRequest = CompilationCacheService_Cas_V1_CASLoadRequest()
        loadRequest.casID = storedID
        let loadResponse = try await service.load(request: loadRequest, context: testContext())
        guard case let .data(blob) = loadResponse.contents,
              case let .data(loadedBytes) = blob.blob.contents
        else {
            Issue.record("CAS Load did not return the saved blob.")
            return
        }

        #expect(loadedBytes == bytes)
    }

    @Test
    func loadHonorsWriteToDiskAndCleansResponseFiles() async throws {
        let storage = InMemoryStorage()
        let identifier = try await storage.save(
            ByteStreamSupport.make(Data([0x41, 0x42, 0x43]))
        )
        let responseDirectory = FileManager.default.temporaryDirectory
            .appending(path: "x8-response-" + UUID().uuidString)
        let fileStore = XcodeCacheResponseFileStore(directory: responseDirectory)
        let service = XcodeCacheCASService(
            casStore: storage,
            responseFileStore: fileStore
        )
        defer { fileStore.cleanup() }

        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID = makeWireID(identifier)
        request.writeToDisk = true

        let response = try await service.load(request: request, context: testContext())

        guard case let .data(blob) = response.contents,
              case let .filePath(path) = blob.blob.contents
        else {
            Issue.record("CAS Load did not return a response file.")
            return
        }
        #expect(try Data(contentsOf: URL(filePath: path)) == Data([0x41, 0x42, 0x43]))

        fileStore.cleanup()
        #expect(FileManager.default.fileExists(atPath: path) == false)
    }

    @Test
    func actionCacheRoundTripPreservesOpaqueEntries() async throws {
        let storage = InMemoryStorage()
        let metrics = X8CacheMetricsStore()
        let service = XcodeCacheActionCacheService(
            actionCacheStore: storage,
            metrics: metrics
        )
        let key = Data([0x41, 0x00, 0x42])
        let value = [
            "value": Data([0x51, 0xFF]),
            "metadata": Data([0x52]),
        ]
        var putRequest = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        putRequest.key = key
        putRequest.value.entries = value

        let putResponse = try await service.putValue(request: putRequest, context: testContext())
        var getRequest = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        getRequest.key = key
        let getResponse = try await service.getValue(request: getRequest, context: testContext())

        #expect(putResponse.hasError == false)
        #expect(getResponse.outcome == .success)
        #expect(getResponse.value.entries == value)

        let snapshot = await metrics.snapshot()
        #expect(snapshot.bytesUploaded == 3)
        #expect(snapshot.bytesDownloaded == 3)
    }

    @Test
    func missingCASRecordUsesObjectNotFoundOutcome() async throws {
        let storage = InMemoryStorage()
        let casService = XcodeCacheCASService(casStore: storage)
        var casRequest = CompilationCacheService_Cas_V1_CASGetRequest()
        casRequest.casID = makeWireID(CASDataID(rawValue: Data([0x61])))

        let casResponse = try await casService.get(request: casRequest, context: testContext())

        #expect(casResponse.outcome == .objectNotFound)
    }

    @Test
    func missingCASBlobUsesObjectNotFoundOutcome() async throws {
        let storage = InMemoryStorage()
        let casService = XcodeCacheCASService(casStore: storage)
        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID = makeWireID(CASDataID(rawValue: Data([0x62])))

        let response = try await casService.load(request: request, context: testContext())

        #expect(response.outcome == .objectNotFound)
    }

    @Test
    func missingActionCacheValueUsesKeyNotFoundOutcome() async throws {
        let storage = InMemoryStorage()
        let actionService = XcodeCacheActionCacheService(actionCacheStore: storage)
        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = Data([0x63])

        let response = try await actionService.getValue(
            request: request,
            context: testContext()
        )

        #expect(response.outcome == .keyNotFound)
    }

    @Test
    func casBackendFailureBecomesProtocolErrorResponse() async throws {
        let service = XcodeCacheCASService(casStore: FailingStorage())
        var request = CompilationCacheService_Cas_V1_CASGetRequest()
        request.casID = makeWireID(CASDataID(rawValue: Data([0x64])))

        let response = try await service.get(request: request, context: testContext())

        #expect(response.outcome == .error)
        #expect(response.error.description_p == "backend failure")
    }

    @Test
    func casPutBackendFailureRecordsRemoteError() async throws {
        let metrics = X8CacheMetricsStore()
        let service = XcodeCacheCASService(casStore: FailingStorage(), metrics: metrics)
        var putRequest = CompilationCacheService_Cas_V1_CASPutRequest()
        putRequest.data.blob = makeBytes(Data([0x71]))

        let response = try await service.put(request: putRequest, context: testContext())

        #expect(response.error.description_p == "backend failure")
        let snapshot = await metrics.snapshot()
        #expect(snapshot.putRequests == 1)
        #expect(snapshot.remoteErrors == 1)
    }

    @Test
    func casSaveBackendFailureRecordsRemoteError() async throws {
        let metrics = X8CacheMetricsStore()
        let service = XcodeCacheCASService(casStore: FailingStorage(), metrics: metrics)
        var saveRequest = CompilationCacheService_Cas_V1_CASSaveRequest()
        saveRequest.data.blob = makeBytes(Data([0x72]))

        let response = try await service.save(request: saveRequest, context: testContext())

        #expect(response.error.description_p == "backend failure")
        let snapshot = await metrics.snapshot()
        #expect(snapshot.putRequests == 1)
        #expect(snapshot.remoteErrors == 1)
    }

    @Test
    func actionCacheBackendFailureBecomesProtocolErrorResponse() async throws {
        let service = XcodeCacheActionCacheService(actionCacheStore: FailingStorage())
        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = Data([0x65])

        let response = try await service.getValue(request: request, context: testContext())

        #expect(response.outcome == .error)
        #expect(response.error.description_p == "backend failure")
    }

    private func testContext() -> GRPCCore.ServerContext {
        ServerContext(
            descriptor: .init(fullyQualifiedService: "x8.test", method: "test"),
            remotePeer: "test",
            localPeer: "test",
            cancellation: .init()
        )
    }

    private func makeWireID(_ id: CASDataID) -> CompilationCacheService_Cas_V1_CASDataID {
        var result = CompilationCacheService_Cas_V1_CASDataID()
        result.id = id.rawValue
        return result
    }

    private func makeBytes(_ data: Data) -> CompilationCacheService_Cas_V1_CASBytes {
        var result = CompilationCacheService_Cas_V1_CASBytes()
        result.contents = .data(data)
        return result
    }

    private func makeBytes(filePath: String) -> CompilationCacheService_Cas_V1_CASBytes {
        var result = CompilationCacheService_Cas_V1_CASBytes()
        result.contents = .filePath(filePath)
        return result
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
