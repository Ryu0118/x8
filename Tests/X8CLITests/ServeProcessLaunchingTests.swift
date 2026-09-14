import Foundation
import Testing
@testable import X8CLI

@Suite("Detached serve process launch plans")
struct ServeProcessLaunchingTests {
    @Test
    func fakeLauncherRecordsTheGivenPlan() throws {
        let launcher = RecordingServeProcessLauncher(pidToReturn: 4321)
        let plan = ServeProcessLaunchPlan(
            executablePath: "/usr/bin/x8",
            arguments: ["serve", "--child-ready-fd", "3"],
            environment: ["FOO": "bar"],
            stdioLogURL: URL(filePath: "/tmp/serve.log"),
            readinessWriteFileDescriptor: 9
        )

        let pid = try launcher.launch(plan)

        #expect(pid == 4321)
        let recorded = try #require(launcher.recordedPlan)
        #expect(recorded.executablePath == "/usr/bin/x8")
        #expect(recorded.arguments == ["serve", "--child-ready-fd", "3"])
        #expect(recorded.environment == ["FOO": "bar"])
        #expect(recorded.stdioLogURL == URL(filePath: "/tmp/serve.log"))
        #expect(recorded.readinessWriteFileDescriptor == 9)
    }

    @Test
    func fakeLauncherPropagatesAConfiguredFailure() {
        struct LaunchFailure: Error, Equatable {}
        let launcher = RecordingServeProcessLauncher(pidToReturn: 0, failure: LaunchFailure())
        let plan = ServeProcessLaunchPlan(
            executablePath: "/usr/bin/x8",
            arguments: [],
            environment: [:],
            stdioLogURL: URL(filePath: "/tmp/serve.log"),
            readinessWriteFileDescriptor: 9
        )

        #expect(throws: LaunchFailure()) {
            try launcher.launch(plan)
        }
    }
}

final class RecordingServeProcessLauncher: ServeProcessLaunching, @unchecked Sendable {
    private(set) var recordedPlan: ServeProcessLaunchPlan?
    private let pidToReturn: pid_t
    private let failure: (any Error)?

    init(pidToReturn: pid_t, failure: (any Error)? = nil) {
        self.pidToReturn = pidToReturn
        self.failure = failure
    }

    func launch(_ plan: ServeProcessLaunchPlan) throws -> pid_t {
        recordedPlan = plan
        if let failure {
            throw failure
        }
        return pidToReturn
    }
}
