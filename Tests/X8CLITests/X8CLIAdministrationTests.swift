import Testing
@testable import X8CLI
import X8Storage

@Suite("Shared administration commands respect capabilities and deletion gates")
struct X8CLIAdministrationTests {
    @Test(arguments: [[], ["--dry-run"], ["--confirm", "--dry-run"], ["--confirm"]])
    func onlyDeletesWithExplicitConfirmation(flags: [String]) async {
        let recorder = CLIRecorder()
        let cli = recorder.capturing(X8CLI(
            configuration: { try X8CLIConfiguration(value: (), profileID: "admin-test") },
            storage: { _ in AgeManagedTestStorage(recorder: recorder) },
            shutdown: { _ in recorder.record("close") }
        ))
        let status = await cli.run(arguments: ["cache", "purge", "--scope", "staging", "--older-than", "1d"] + flags)
        #expect(status == 0)
        #expect(recorder.events.contains("delete:old-object") == (flags == ["--confirm"]))
        #expect(recorder.events.filter { $0 == "close" }.count == 1)
        if flags == ["--confirm"] {
            #expect(recorder.events.contains { $0.contains("skipped 1") })
        }
    }

    @Test
    func reportsMissingAdministrationAndClosesStorage() async {
        let recorder = CLIRecorder()
        let cli = recorder.capturing(X8CLI(
            configuration: { try X8CLIConfiguration(value: (), profileID: "data-only") },
            storage: { _ in DataOnlyTestStorage() },
            shutdown: { _ in recorder.record("close") }
        ))
        #expect(await cli.run(arguments: ["cache", "purge", "--scope", "staging", "--older-than", "1d"]) != 0)
        #expect(recorder.events.contains { $0.contains("does not support cache administration") })
        #expect(recorder.events.filter { $0 == "close" }.count == 1)
    }

    @Test
    func refusesCASPurgeWithoutRetentionBeforeListing() async {
        let recorder = CLIRecorder()
        let cli = recorder.capturing(X8CLI(
            configuration: { try X8CLIConfiguration(value: (), profileID: "no-retention") },
            storage: { _ in AgeManagedTestStorage(recorder: recorder) },
            shutdown: { _ in recorder.record("close") }
        ))
        #expect(await cli.run(arguments: ["cache", "purge", "--scope", "cas", "--grace-period", "1d", "--confirm"]) != 0)
        #expect(!recorder.events.contains("list"))
        #expect(recorder.events.contains { $0.contains("authoritative retention store") })
        #expect(recorder.events.filter { $0 == "close" }.count == 1)
    }

    @Test
    func doesNotCloseAnUnconstructedClient() async {
        let recorder = CLIRecorder()
        let cli = recorder.capturing(X8CLI(
            configuration: { try X8CLIConfiguration(value: (), profileID: "failed-open") },
            storage: { _ -> DataOnlyTestStorage in throw FactoryFailure.connectionFailed },
            shutdown: { _ in recorder.record("close") }
        ))
        #expect(await cli.run(arguments: ["cache", "purge", "--scope", "staging", "--older-than", "1d"]) != 0)
        #expect(!recorder.events.contains("close"))
    }
}

private enum FactoryFailure: Error {
    case connectionFailed
}
