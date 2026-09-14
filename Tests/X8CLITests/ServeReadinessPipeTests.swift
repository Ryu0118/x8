import Darwin
import Testing
@testable import X8CLI

@Suite("Detached serve readiness pipe")
struct ServeReadinessPipeTests {
    @Test
    func readyWhenTheChildWritesItsByte() async throws {
        var pipe = try ServeReadinessPipe()
        // A real spawned child holds its own duplicate of the write end,
        // separate from the parent's copy; `dup` simulates that here since
        // this test never actually forks a process.
        let childFileDescriptor = dup(pipe.childWriteFileDescriptor)
        pipe.closeWriteEnd()
        var byte: UInt8 = 1
        _ = withUnsafeBytes(of: &byte) { write(childFileDescriptor, $0.baseAddress, 1) }
        close(childFileDescriptor)

        let outcome = try await pipe.waitForReadiness(
            pid: 1,
            timeout: .seconds(2),
            signaling: NeverCalledSignaling()
        )

        #expect(outcome == .ready)
    }

    @Test
    func exitedBeforeReadyWhenTheChildClosesWithoutWriting() async throws {
        var pipe = try ServeReadinessPipe()
        let childFileDescriptor = dup(pipe.childWriteFileDescriptor)
        pipe.closeWriteEnd()
        close(childFileDescriptor)
        let signaling = RecordingProcessSignaling(waitpidStatus: 42)

        let outcome = try await pipe.waitForReadiness(
            pid: 7,
            timeout: .seconds(2),
            signaling: signaling
        )

        #expect(outcome == .exitedBeforeReady(status: 42))
        #expect(signaling.waitpidCalls == [7])
        #expect(signaling.killCalls.isEmpty)
    }

    @Test
    func timesOutAndKillsWhenNothingArrives() async throws {
        var pipe = try ServeReadinessPipe()
        // Simulates the child inheriting its own copy of the write end and
        // never closing it: the parent closes its own copy (as real launch
        // code does immediately after spawning), but the read end still
        // never sees EOF because the child's copy is still open.
        let childFileDescriptor = dup(pipe.childWriteFileDescriptor)
        pipe.closeWriteEnd()
        let signaling = RecordingProcessSignaling(waitpidStatus: nil)

        let outcome = try await pipe.waitForReadiness(
            pid: 9,
            timeout: .milliseconds(200),
            signaling: signaling
        )

        #expect(outcome == .timedOut)
        #expect(signaling.killCalls == [SignalCall(pid: 9, signal: SIGKILL)])
        close(childFileDescriptor)
    }
}

struct SignalCall: Equatable {
    let pid: pid_t
    let signal: Int32
}

final class RecordingProcessSignaling: ProcessSignaling, @unchecked Sendable {
    private(set) var killCalls: [SignalCall] = []
    private(set) var waitpidCalls: [pid_t] = []
    private let waitpidStatus: Int32?

    init(waitpidStatus: Int32?) {
        self.waitpidStatus = waitpidStatus
    }

    func kill(_ pid: pid_t, _ signal: Int32) throws {
        killCalls.append(SignalCall(pid: pid, signal: signal))
    }

    func waitpid(_ pid: pid_t) -> Int32? {
        waitpidCalls.append(pid)
        return waitpidStatus
    }
}

struct NeverCalledSignaling: ProcessSignaling {
    func kill(_: pid_t, _: Int32) throws {
        Issue.record("kill should not be called when the child signaled readiness.")
    }

    func waitpid(_: pid_t) -> Int32? {
        Issue.record("waitpid should not be called when the child signaled readiness.")
        return nil
    }
}
