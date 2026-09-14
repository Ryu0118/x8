import Darwin

/// Sends signals to and reaps detached child processes.
///
/// This is the only place process-signal system calls belong in this
/// package's detach/stop feature: `X8Kit` never sends signals, so the
/// detach launcher and `stop` command depend on this protocol instead of
/// calling `kill`/`waitpid` directly, keeping those call sites fake-testable.
protocol ProcessSignaling: Sendable {
    /// Sends `signal` to `pid`.
    ///
    /// A caller that wants "already dead" treated as success rather than a
    /// thrown error should catch ``ProcessSignalingError/noSuchProcess`` and
    /// handle it explicitly; this method reports the raw outcome.
    func kill(_ pid: pid_t, _ signal: Int32) throws

    /// Waits for `pid` to exit and returns its raw `wait`-status, or `nil` if
    /// `pid` is not this process's child.
    func waitpid(_ pid: pid_t) -> Int32?
}

/// Describes why ``ProcessSignaling/kill(_:_:)`` failed.
enum ProcessSignalingError: Error, Equatable {
    /// No process (or process group) can be found matching `pid`.
    case noSuchProcess(pid: pid_t)

    /// The signal could not be sent for a reason other than a missing process.
    case underlying(pid: pid_t, errno: Int32)
}

/// Sends real signals and reaps real child processes via Darwin's libc.
struct LiveProcessSignaling: ProcessSignaling {
    func kill(_ pid: pid_t, _ signal: Int32) throws {
        guard Darwin.kill(pid, signal) != 0 else { return }
        let code = errno
        guard code != ESRCH else {
            throw ProcessSignalingError.noSuchProcess(pid: pid)
        }
        throw ProcessSignalingError.underlying(pid: pid, errno: code)
    }

    func waitpid(_ pid: pid_t) -> Int32? {
        var status: Int32 = 0
        let result = Darwin.waitpid(pid, &status, 0)
        guard result == pid else { return nil }
        return status
    }
}
