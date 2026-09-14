import Foundation

/// Launches a detached `x8 serve` child process.
///
/// This boundary exists so `x8 serve -d`'s parent flow can be tested without
/// spawning a real process: a fake conforming to this protocol records the
/// plan it was given, while ``PosixServeProcessLauncher`` performs the real
/// `posix_spawn`.
protocol ServeProcessLaunching: Sendable {
    /// Spawns the child process described by `plan` and returns its PID.
    func launch(_ plan: ServeProcessLaunchPlan) throws -> pid_t
}

/// Describes one detached child process to spawn.
struct ServeProcessLaunchPlan: Sendable {
    /// The resolved path to the executable to spawn.
    let executablePath: String

    /// The full `argv`, not including `argv[0]`.
    let arguments: [String]

    /// The child's environment, replacing rather than merging with the parent's.
    let environment: [String: String]

    /// Where the child's stdout and stderr are redirected.
    let stdioLogURL: URL

    /// The file descriptor number the child should use to signal readiness.
    ///
    /// The parent's read end of the same pipe is read by
    /// ``ServeReadinessPipe/waitForReadiness(pid:timeout:signaling:)``.
    let readinessWriteFileDescriptor: Int32
}
