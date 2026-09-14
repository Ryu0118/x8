import Darwin
import Foundation

/// Spawns a detached `x8 serve` child with `posix_spawn`.
///
/// The child is moved out of the parent's session (`POSIX_SPAWN_SETSID`) so a
/// terminal hangup does not reach it, and its signal disposition and mask are
/// reset (`POSIX_SPAWN_SETSIGDEF`/`POSIX_SPAWN_SETSIGMASK`) so it receives
/// `SIGINT`/`SIGTERM`/`SIGHUP`/`SIGPIPE` normally even if the parent was
/// ignoring them. `POSIX_SPAWN_CLOEXEC_DEFAULT` closes every inherited
/// descriptor except the ones this launcher explicitly keeps open through
/// `file_actions`, so the daemon does not hold the parent's terminal, sockets,
/// or other file descriptors open indefinitely.
struct PosixServeProcessLauncher: ServeProcessLaunching {
    /// The fixed descriptor number the child uses to signal readiness.
    static let readinessFileDescriptor: Int32 = 3

    func launch(_ plan: ServeProcessLaunchPlan) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }

        try configureFileActions(&fileActions, plan: plan)
        try configureAttributes(&attributes)

        let argv = ([plan.executablePath] + plan.arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let environment = plan.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { environment.forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, plan.executablePath, &fileActions, &attributes, argv, environment)
        guard status == 0 else {
            throw PosixServeProcessLauncherError.spawnFailed(errno: status)
        }
        return pid
    }

    private func configureFileActions(
        _ fileActions: inout posix_spawn_file_actions_t?,
        plan: ServeProcessLaunchPlan
    ) throws {
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(
            &fileActions, 1, plan.stdioLogURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o600
        )
        posix_spawn_file_actions_adddup2(&fileActions, 1, 2)
        posix_spawn_file_actions_addinherit_np(&fileActions, plan.readinessWriteFileDescriptor)
        posix_spawn_file_actions_adddup2(
            &fileActions, plan.readinessWriteFileDescriptor, Self.readinessFileDescriptor
        )
    }

    private func configureAttributes(_ attributes: inout posix_spawnattr_t?) throws {
        var signalDefaultSet = sigset_t()
        sigemptyset(&signalDefaultSet)
        sigaddset(&signalDefaultSet, SIGINT)
        sigaddset(&signalDefaultSet, SIGTERM)
        sigaddset(&signalDefaultSet, SIGHUP)
        sigaddset(&signalDefaultSet, SIGPIPE)
        posix_spawnattr_setsigdefault(&attributes, &signalDefaultSet)

        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        posix_spawnattr_setsigmask(&attributes, &signalMask)

        let flags = Int16(
            POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        )
        posix_spawnattr_setflags(&attributes, flags)
    }
}

/// Errors raised while spawning a detached `x8 serve` child process.
enum PosixServeProcessLauncherError: Error, Equatable {
    /// `posix_spawn` returned a non-zero status, carried as its `errno` value.
    case spawnFailed(errno: Int32)
}
