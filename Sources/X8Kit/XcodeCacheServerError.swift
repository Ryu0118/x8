/// Errors raised while establishing an Xcode cache server.
///
/// These cases describe the cache endpoint readiness and ownership boundary.
/// They are thrown when startup cannot establish a safe endpoint. The error
/// does not represent an external client process or its exit status.
package enum XcodeCacheServerError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The cache server did not create its socket before the startup deadline.
    case startupTimedOut(socketPath: String)

    /// The cache server stopped before its socket became ready.
    case stoppedBeforeReady(socketPath: String)

    /// A standalone server cannot safely use an existing socket path.
    case socketPathOccupied(socketPath: String)

    /// A human-readable description suitable for CLI diagnostics.
    package var description: String {
        switch self {
        case let .startupTimedOut(socketPath):
            "The cache server did not become ready at \(socketPath)."
        case let .stoppedBeforeReady(socketPath):
            "The cache server stopped before becoming ready at \(socketPath)."
        case let .socketPathOccupied(socketPath):
            "The cache socket path is already occupied by an existing endpoint: \(socketPath)."
        }
    }
}
