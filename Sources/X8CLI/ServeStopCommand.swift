import ArgumentParser
import Foundation
import X8Kit

struct ServeStopCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop a detached `x8 serve -d` process."
    )

    private static let gracefulShutdownTimeout: Duration = .seconds(10)
    private static let gracefulShutdownPollInterval: Duration = .milliseconds(100)

    func run(context: X8CommandContext) async throws {
        let configured = try await context.configuredStorage()
        let profileID = configured.configuration.profileID
        let pidFileURL = XcodeServeRunner.defaultPIDFileURL(profileID: profileID)
        let socketPath = XcodeServeRunner.defaultSocketPath(profileID: profileID)

        guard let record = Self.readProcessRecord(at: pidFileURL) else {
            context.logger.info("No detached `x8 serve` process is running for this profile.")
            return
        }

        let livenessProbe = LiveProcessLivenessProbe()
        guard livenessProbe.isAlive(record) else {
            context.logger.info("No detached `x8 serve` process is running for this profile.")
            Self.cleanUp(pidFileURL: pidFileURL, socketPath: socketPath)
            return
        }

        try await Self.stop(
            record: record,
            livenessProbe: livenessProbe,
            signaling: LiveProcessSignaling(),
            pidFileURL: pidFileURL,
            socketPath: socketPath
        )
        context.logger.info("✅ Stopped the detached `x8 serve` process (pid \(record.pid)).", metadata: .color(.green))
    }

    /// Signals graceful shutdown, waits for exit, force-kills on timeout, and cleans up.
    ///
    /// - Parameters:
    ///   - gracefulShutdownTimeout: How long to wait for `SIGTERM` to take
    ///     effect before escalating to `SIGKILL`. Tests inject a short value.
    ///   - gracefulShutdownPollInterval: How often liveness is re-checked
    ///     while waiting. Tests inject a short value.
    static func stop(
        record: XcodeServeProcessRecord,
        livenessProbe: any ProcessLivenessProbing,
        signaling: any ProcessSignaling,
        pidFileURL: URL,
        socketPath: String,
        gracefulShutdownTimeout: Duration = gracefulShutdownTimeout,
        gracefulShutdownPollInterval: Duration = gracefulShutdownPollInterval
    ) async throws {
        do {
            try signaling.kill(record.pid, SIGTERM)
        } catch ProcessSignalingError.noSuchProcess {
            cleanUp(pidFileURL: pidFileURL, socketPath: socketPath)
            return
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: gracefulShutdownTimeout)
        while clock.now < deadline, livenessProbe.isAlive(record) {
            try await Task.sleep(for: gracefulShutdownPollInterval)
        }
        if livenessProbe.isAlive(record) {
            try? signaling.kill(record.pid, SIGKILL)
        }
        cleanUp(pidFileURL: pidFileURL, socketPath: socketPath)
    }

    private static func cleanUp(pidFileURL: URL, socketPath: String) {
        try? FileManager.default.removeItem(at: pidFileURL)
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private static func readProcessRecord(at url: URL) -> XcodeServeProcessRecord? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(XcodeServeProcessRecord.self, from: data)
    }
}
