import Darwin
import Foundation
import Testing
@testable import X8CLI
import X8Kit

@Suite("Detached serve stop signaling")
struct ServeStopCommandTests {
    @Test
    func sendsTermThenCleansUpOnceLivenessReportsDead() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-stop-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFileURL = directory.appending(path: "serve.pid")
        let socketPath = directory.appending(path: "cache.sock").path
        try FileManager.default.createFile(atPath: pidFileURL.path, contents: JSONEncoder().encode(
            XcodeServeProcessRecord(pid: 123, startTime: 1, executablePath: "/usr/bin/x8")
        ))
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let signaling = RecordingProcessSignaling(waitpidStatus: nil)
        let livenessProbe = ScriptedLivenessProbe(aliveAnswers: [true, false])

        try await ServeStopCommand.stop(
            record: XcodeServeProcessRecord(pid: 123, startTime: 1, executablePath: "/usr/bin/x8"),
            livenessProbe: livenessProbe,
            signaling: signaling,
            pidFileURL: pidFileURL,
            socketPath: socketPath
        )

        #expect(signaling.killCalls == [SignalCall(pid: 123, signal: SIGTERM)])
        #expect(FileManager.default.fileExists(atPath: pidFileURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: socketPath) == false)
    }

    @Test
    func escalatesToSigkillWhenGracefulShutdownNeverCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-stop-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFileURL = directory.appending(path: "serve.pid")
        let socketPath = directory.appending(path: "cache.sock").path

        let signaling = RecordingProcessSignaling(waitpidStatus: nil)
        let livenessProbe = AlwaysAliveScriptedProbe()

        try await ServeStopCommand.stop(
            record: XcodeServeProcessRecord(pid: 456, startTime: 1, executablePath: "/usr/bin/x8"),
            livenessProbe: livenessProbe,
            signaling: signaling,
            pidFileURL: pidFileURL,
            socketPath: socketPath,
            gracefulShutdownTimeout: .milliseconds(50),
            gracefulShutdownPollInterval: .milliseconds(10)
        )

        #expect(signaling.killCalls.contains(SignalCall(pid: 456, signal: SIGTERM)))
        #expect(signaling.killCalls.contains(SignalCall(pid: 456, signal: SIGKILL)))
    }

    @Test
    func doubleStopIsIdempotentWhenProcessIsAlreadyGone() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-stop-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFileURL = directory.appending(path: "serve.pid")
        let socketPath = directory.appending(path: "cache.sock").path

        let signaling = NoSuchProcessSignaling()
        let livenessProbe = AlwaysAliveScriptedProbe()

        try await ServeStopCommand.stop(
            record: XcodeServeProcessRecord(pid: 789, startTime: 1, executablePath: "/usr/bin/x8"),
            livenessProbe: livenessProbe,
            signaling: signaling,
            pidFileURL: pidFileURL,
            socketPath: socketPath
        )

        #expect(FileManager.default.fileExists(atPath: pidFileURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: socketPath) == false)
    }
}

private final class ScriptedLivenessProbe: ProcessLivenessProbing, @unchecked Sendable {
    private var answers: [Bool]

    init(aliveAnswers: [Bool]) {
        answers = aliveAnswers
    }

    func isAlive(_: XcodeServeProcessRecord) -> Bool {
        guard !answers.isEmpty else { return false }
        return answers.removeFirst()
    }
}

private struct AlwaysAliveScriptedProbe: ProcessLivenessProbing {
    func isAlive(_: XcodeServeProcessRecord) -> Bool {
        true
    }
}

private struct NoSuchProcessSignaling: ProcessSignaling {
    func kill(_ pid: pid_t, _: Int32) throws {
        throw ProcessSignalingError.noSuchProcess(pid: pid)
    }

    func waitpid(_: pid_t) -> Int32? {
        nil
    }
}
