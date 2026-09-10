import ArgumentParser
import Testing
@testable import X8CLI
import X8Storage

@Suite("Shared commands resolve custom configuration only when needed")
struct X8CLICommandTests {
    @Test(arguments: [["--help"], ["--version"], ["help", "serve"], ["config", "--help"], ["--generate-completion-script", "zsh"]])
    func bypassesConfigurationForParserRequests(arguments: [String]) async {
        let recorder = CLIRecorder()
        let cli = recorder.capturing(X8CLI(
            configuration: {
                recorder.record("load")
                throw ValidationError("No configuration exists")
            },
            storage: { (_: String) in InMemoryStorage() }
        ))
        #expect(await cli.run(arguments: arguments) == 0)
        #expect(!recorder.events.contains("load"))
        #expect(recorder.events.contains { $0.hasPrefix("stdout:") })
    }

    @Test(arguments: [["config", "validate"], ["config", "show"]])
    func resolvesOnceWithoutOpeningStorage(arguments: [String]) async {
        let recorder = CLIRecorder()
        let cli = makeCLI(recorder: recorder, profileID: "custom-cache")
        #expect(await cli.run(arguments: arguments) == 0)
        #expect(recorder.events.filter { $0 == "load:custom-cache" }.count == 1)
        #expect(!recorder.events.contains { $0.hasPrefix("open:") || $0 == "close" })
    }

    @Test
    func keepsCustomConfigurationAndOutputIsolated() async {
        let first = CLIRecorder()
        let second = CLIRecorder()
        async let firstStatus = makeCLI(recorder: first, profileID: "first").run(arguments: ["config", "show"])
        async let secondStatus = makeCLI(recorder: second, profileID: "second").run(arguments: ["config", "show"])
        #expect(await firstStatus == 0)
        #expect(await secondStatus == 0)
        #expect(first.events.contains("stdout:domain=first"))
        #expect(second.events.contains("stdout:domain=second"))
        #expect(!first.events.joined().contains("second"))
        #expect(!second.events.joined().contains("first"))
    }

    @Test(arguments: [["serve", "--print-socket", "--print-cache-settings"], ["cache", "purge", "--scope", "wrong"]])
    func rejectsInvalidArgumentsBeforeLoading(arguments: [String]) async {
        let recorder = CLIRecorder()
        #expect(await makeCLI(recorder: recorder).run(arguments: arguments) == 64)
        #expect(!recorder.events.contains { $0.hasPrefix("load:") })
        #expect(recorder.events.contains { $0.hasPrefix("stderr:") })
    }

    @Test
    func preservesUndocumentedDiagnosticWithoutAdvertisingIt() throws {
        #expect(try X8RootCommand.parseAsRoot(["stats"]) is StatsCommand)
        #expect(!X8RootCommand.helpMessage().contains("stats"))
    }

    @Test
    func preservesXcodeArgumentPassthrough() throws {
        let arguments = ["xcodebuild", "xcodebuild", "-scheme", "App", "--help", "SETTING=a b"]
        let parsed = try #require(X8RootCommand.parseAsRoot(arguments) as? XcodeBuildCommand)
        #expect(parsed.arguments == Array(arguments.dropFirst()))
        let implicit = try #require(X8RootCommand.parseAsRoot(["/Applications/Xcode.app/usr/bin/xcodebuild", "build"]) as? XcodeBuildCommand)
        #expect(implicit.arguments == ["/Applications/Xcode.app/usr/bin/xcodebuild", "build"])
    }

    @Test
    func preservesFactoryInputAndClosesStorageAfterPurge() async {
        let recorder = CLIRecorder()
        let cli = makeCLI(recorder: recorder, profileID: "custom-cache")
        #expect(await cli.run(arguments: ["cache", "purge", "--scope", "staging", "--older-than", "1d", "--dry-run"]) == 0)
        #expect(recorder.events.filter { !$0.hasPrefix("stderr:") } == ["load:custom-cache", "open:custom-cache", "close"])
    }

    private func makeCLI(recorder: CLIRecorder, profileID: String = "custom-cache") -> X8CLI {
        recorder.capturing(X8CLI(
            configuration: {
                recorder.record("load:\(profileID)")
                return try X8CLIConfiguration(
                    value: profileID,
                    profileID: profileID,
                    displayFields: [("domain", profileID)]
                )
            },
            storage: { value in
                recorder.record("open:\(value)")
                return InMemoryStorage()
            },
            shutdown: { _ in recorder.record("close") }
        ))
    }
}
