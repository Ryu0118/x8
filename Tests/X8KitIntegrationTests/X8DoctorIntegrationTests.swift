import Foundation
import Testing
import X8Core
import X8Kit
import X8Storage

@Suite("X8 doctor protocol check")
struct X8DoctorIntegrationTests {
    @Test("connects to the proxy and exercises all six RPCs")
    func checksProtocolOverUnixSocket() async throws {
        let result = try await X8Doctor().checkProxy()

        #expect(result.rpcMethodsExercised == 6)
        #expect(FileManager.default.fileExists(atPath: result.socketPath) == false)
    }

    @Test("probes the configured storage with a read-only key")
    func checksStorageRead() async throws {
        let storage = RecordingActionCacheStore()

        let result = try await X8Doctor().check(actionCacheStore: storage)

        #expect(result.proxy.rpcMethodsExercised == 6)
        #expect(await storage.readCount == 1)
    }
}

private actor RecordingActionCacheStore: ActionCacheStore {
    private(set) var readCount = 0

    func getValue(for _: ActionCacheKey) async throws -> ActionCacheValue? {
        readCount += 1
        return nil
    }

    func putValue(_: ActionCacheValue, for _: ActionCacheKey) async throws {}
}
