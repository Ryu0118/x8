/// Determines whether a recorded detached process is still the one running.
///
/// A live implementation belongs to a frontend, not this package: checking
/// whether a PID is alive is itself a signal-adjacent system call, and this
/// package's dependencies never send or probe process signals. `X8CLI`
/// supplies the live implementation and injects it wherever this package
/// needs a liveness answer, such as ``XcodeServeRunner``'s stale-socket check.
public protocol ProcessLivenessProbing: Sendable {
    /// Returns whether `record` still identifies a running process.
    ///
    /// An implementation must also account for PID reuse: a PID that is
    /// alive but no longer matches `record`'s start time or executable path
    /// belongs to an unrelated process and is not "alive" for this purpose.
    func isAlive(_ record: XcodeServeProcessRecord) -> Bool
}

/// Treats every recorded process as alive, so a caller without a live probe
/// never reclaims a socket whose pidfile it cannot disprove. A socket with no
/// pidfile at all is unaffected: it is reclaimed once nothing answers on it,
/// regardless of which liveness probe is in use.
public struct AlwaysAliveProcessLivenessProbe: ProcessLivenessProbing {
    /// Creates a probe that reports every record as alive.
    public init() {}

    /// Always returns `true`.
    public func isAlive(_: XcodeServeProcessRecord) -> Bool {
        true
    }
}
