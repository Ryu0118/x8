import Darwin
import Foundation
import X8Kit

/// Checks a detached `x8 serve` process's liveness against the real process table.
///
/// A PID alone cannot distinguish the process this package started from an
/// unrelated process that later reused the same PID, so this probe also
/// compares the kernel's recorded start time for that PID against the
/// pidfile's `startTime`, within a small tolerance for encoding rounding.
package struct LiveProcessLivenessProbe: ProcessLivenessProbing {
    /// The allowed drift, in seconds, between a recorded and observed start time.
    private static let startTimeTolerance: Double = 1

    /// Creates a probe backed by the real process table.
    package init() {}

    /// Returns whether `record`'s PID is running and still matches its start time.
    ///
    /// `kill(pid, 0)` alone answers "is some process running at this PID,"
    /// which is not enough under PID reuse; comparing `sysctl`'s
    /// `kp_proc.p_starttime` against the recorded value rules out a
    /// coincidentally-reused PID belonging to an unrelated process.
    package func isAlive(_ record: XcodeServeProcessRecord) -> Bool {
        switch Self.probeKill(record.pid) {
        case .noSuchProcess:
            return false
        case .ownedByAnotherUser:
            // A process alive but owned by another user cannot be inspected
            // further. Treat it conservatively as still alive rather than
            // reclaiming a socket this process cannot prove is unowned.
            return true
        case .aliveOrUnknown:
            break
        }
        guard let startTime = Self.startTime(ofProcess: record.pid) else {
            // The PID answered `kill` but its process info vanished before
            // sysctl could read it (a race with the process exiting). Treat
            // that as no longer alive rather than trusting a stale answer.
            return false
        }
        return abs(startTime - record.startTime) <= Self.startTimeTolerance
    }

    /// Builds a process record identifying the currently running process.
    ///
    /// Returns `nil` when either the current process's start time or
    /// executable path cannot be resolved, since a record missing either
    /// field can never be matched back by ``isAlive(_:)``.
    static func currentProcessRecord(executablePath: String) -> XcodeServeProcessRecord? {
        let pid = getpid()
        guard let startTime = startTime(ofProcess: pid) else { return nil }
        return XcodeServeProcessRecord(pid: pid, startTime: startTime, executablePath: executablePath)
    }

    /// Classifies a `kill(pid, 0)` liveness probe's raw outcome.
    private static func probeKill(_ pid: pid_t) -> KillProbeOutcome {
        guard kill(pid, 0) != 0 else { return .aliveOrUnknown }
        return switch errno {
        case ESRCH: .noSuchProcess
        case EPERM: .ownedByAnotherUser
        default: .aliveOrUnknown
        }
    }

    /// Returns a process's start time, in seconds since the Unix epoch, via `sysctl`.
    private static func startTime(ofProcess pid: pid_t) -> Double? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size == MemoryLayout<kinfo_proc>.stride else { return nil }
        let startTime = info.kp_proc.p_starttime
        return Double(startTime.tv_sec) + Double(startTime.tv_usec) / 1_000_000
    }
}

/// The classified outcome of one `kill(pid, 0)` liveness probe.
private enum KillProbeOutcome {
    /// No process exists at the probed PID.
    case noSuchProcess

    /// A process exists but is owned by a different user.
    case ownedByAnotherUser

    /// The probe succeeded (the PID is this process's own or a child it can
    /// signal), or failed for a reason other than the two cases above.
    case aliveOrUnknown
}
