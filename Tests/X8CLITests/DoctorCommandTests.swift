import Foundation
import Testing
@testable import X8CLI
import X8Core
import X8Storage

@Suite("Doctor reports which check failed")
struct DoctorCommandTests {
    @Test
    func reportsEarlierSuccessesBeforeAFailingStorageRead() async {
        let recorder = CLIRecorder()
        let cli = recorder.capturing(X8CLI(
            configuration: {
                try X8CLIConfiguration(
                    value: (),
                    profileID: "doctor-fail",
                    credentialSource: "static (redacted)"
                )
            },
            storage: { _ in FailingActionCacheStorage() }
        ))

        let status = await cli.run(arguments: ["doctor"])

        #expect(status != 0)
        let output = recorder.events.joined(separator: "\n")
        #expect(output.contains("configuration: ok"))
        #expect(output.contains("credentials: static (redacted)"))
        #expect(output.contains("protocol: ok"))
        #expect(output.contains("❌ storage-read: failed"))
        #expect(output.contains("boom"))
    }

    @Test
    func reportsEverySucceedingStepWhenStorageReadSucceeds() async {
        let recorder = CLIRecorder()
        let cli = recorder.capturing(X8CLI(
            configuration: {
                try X8CLIConfiguration(value: (), profileID: "doctor-ok")
            },
            storage: { _ in InMemoryStorage() }
        ))

        let status = await cli.run(arguments: ["doctor"])

        #expect(status == 0)
        let output = recorder.events.joined(separator: "\n")
        #expect(output.contains("configuration: ok"))
        #expect(output.contains("protocol: ok"))
        #expect(output.contains("storage-read: ok"))
        #expect(!output.contains("❌"))
    }
}

private struct DoctorStorageFailure: Error, CustomStringConvertible {
    var description: String {
        "boom"
    }
}

private struct FailingActionCacheStorage: CASStore, ActionCacheStore {
    func get(id _: CASDataID) async throws -> CASObject? {
        nil
    }

    func put(_: CASObject) async throws -> CASDataID {
        CASDataID(rawValue: Data())
    }

    func load(id _: CASDataID) async throws -> ByteStream? {
        nil
    }

    func save(_: ByteStream) async throws -> CASDataID {
        CASDataID(rawValue: Data())
    }

    func getValue(for _: ActionCacheKey) async throws -> ActionCacheValue? {
        throw DoctorStorageFailure()
    }

    func putValue(_: ActionCacheValue, for _: ActionCacheKey) async throws {}
}
