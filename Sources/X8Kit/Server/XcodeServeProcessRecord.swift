import Foundation

/// Identifies one detached `x8 serve` process for later liveness checks.
///
/// `startTime` and `executablePath` exist alongside `pid` so a caller can
/// tell a still-running process from an unrelated process that later reused
/// the same PID. This type only encodes and decodes the record; reading,
/// writing, and interpreting it against the live process table are the
/// caller's responsibility.
package struct XcodeServeProcessRecord: Codable, Sendable, Equatable {
    /// The detached process's identifier.
    package let pid: Int32

    /// The process's start time, in seconds since the Unix epoch.
    package let startTime: Double

    /// The resolved path to the executable the process was spawned from.
    package let executablePath: String

    /// Creates a record identifying one detached process.
    package init(pid: Int32, startTime: Double, executablePath: String) {
        self.pid = pid
        self.startTime = startTime
        self.executablePath = executablePath
    }
}
