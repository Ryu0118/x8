import ArgumentParser

/// Restricts a caller-supplied fixed socket path to one the kernel can bind.
///
/// The macOS `sockaddr_un.sun_path` field holds 104 bytes including the
/// terminating NUL, so any path at or beyond 104 UTF-8 bytes cannot be bound
/// at all. A relative path would resolve against whatever directory a
/// command happens to run from instead of a fixed, team-shared location,
/// defeating the purpose of pinning it.
enum X8SocketPathValidator {
    static func validate(_ socketPath: String) throws {
        guard socketPath.hasPrefix("/") else {
            throw ValidationError("Socket path must be an absolute path.")
        }
        guard socketPath.utf8.count < 104 else {
            throw ValidationError("Socket path must be shorter than 104 bytes.")
        }
    }
}
