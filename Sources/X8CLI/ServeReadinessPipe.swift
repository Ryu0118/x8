import Darwin
import Foundation

/// A pipe a detached `x8 serve` child uses to report readiness to its parent.
///
/// The parent creates one pipe, passes its write end to the child through
/// ``ServeProcessLaunchPlan/readinessWriteFileDescriptor``, and waits on the
/// read end. The child writes exactly one byte once its server has bound its
/// socket, then closes its end; an early exit or a hang before that write is
/// what lets the parent distinguish "started" from "failed" or "wedged."
struct ServeReadinessPipe: ~Copyable {
    private let readFileDescriptor: Int32
    private var writeFileDescriptor: Int32

    /// The descriptor a spawned child inherits to signal readiness.
    var childWriteFileDescriptor: Int32 {
        writeFileDescriptor
    }

    /// Creates the underlying `pipe(2)`, marking the read end close-on-exec.
    ///
    /// The read end must never leak into the spawned child: if it did, the
    /// child would hold its own read end open and a crash-before-ready would
    /// never produce the EOF this type depends on to detect that case.
    init() throws {
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else {
            throw ServeReadinessPipeError.pipeCreationFailed(errno: errno)
        }
        readFileDescriptor = descriptors[0]
        writeFileDescriptor = descriptors[1]
        let flags = fcntl(readFileDescriptor, F_GETFD)
        _ = fcntl(readFileDescriptor, F_SETFD, flags | FD_CLOEXEC)
    }

    /// Closes the parent's own copy of the write end.
    ///
    /// `posix_spawn` duplicates the write end into the child; the parent's
    /// original descriptor is a separate copy of the same pipe. Without
    /// closing it here, the pipe always has a writer open from the parent's
    /// side, so the child closing its own copy would never produce EOF for
    /// ``waitForReadiness(pid:timeout:signaling:)`` to observe. Safe to call
    /// more than once.
    mutating func closeWriteEnd() {
        guard writeFileDescriptor != -1 else { return }
        close(writeFileDescriptor)
        writeFileDescriptor = -1
    }

    /// Waits for the child to signal readiness, exit early, or time out.
    ///
    /// The wait polls the read descriptor from a dedicated thread rather than
    /// blocking a cooperative-pool thread, since `read` on a pipe has no
    /// async-friendly equivalent on Darwin. `timeout` bounds how long an
    /// unresponsive child is tolerated before it is killed and reported as
    /// timed out.
    consuming func waitForReadiness(
        pid: pid_t,
        timeout: Duration,
        signaling: any ProcessSignaling
    ) async throws -> ServeReadinessOutcome {
        let fileDescriptor = readFileDescriptor
        let timeoutMilliseconds = Int32(clamping: timeout.milliseconds)
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<PipeWaitResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.poll(fileDescriptor, timeoutMilliseconds: timeoutMilliseconds))
            }
        }
        close(fileDescriptor)

        switch outcome {
        case .ready:
            return .ready
        case .timedOut:
            try? signaling.kill(pid, SIGKILL)
            return .timedOut
        case .closedWithoutReadiness:
            let status = signaling.waitpid(pid) ?? 0
            return .exitedBeforeReady(status: status)
        }
    }

    /// Blocks the calling thread until the read end is readable or the timeout elapses.
    private static func poll(_ fileDescriptor: Int32, timeoutMilliseconds: Int32) -> PipeWaitResult {
        var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
        let result = Darwin.poll(&descriptor, 1, timeoutMilliseconds)
        guard result > 0 else { return .timedOut }

        var byte: UInt8 = 0
        let bytesRead = read(fileDescriptor, &byte, 1)
        return bytesRead > 0 ? .ready : .closedWithoutReadiness
    }
}

/// The result of a detached child's readiness wait.
enum ServeReadinessOutcome: Sendable, Equatable {
    /// The child wrote its readiness byte; the server is bound and serving.
    case ready

    /// The child exited (or was killed) before it signaled readiness.
    case exitedBeforeReady(status: Int32)

    /// No readiness signal arrived before the deadline; the child was killed.
    case timedOut
}

/// Errors raised while creating a readiness pipe.
enum ServeReadinessPipeError: Error, Equatable {
    /// `pipe(2)` failed, carried as its `errno` value.
    case pipeCreationFailed(errno: Int32)
}

/// The raw outcome of one blocking poll-and-read cycle on the readiness pipe.
private enum PipeWaitResult {
    case ready
    case timedOut
    case closedWithoutReadiness
}

private extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = (components.seconds, components.attoseconds)
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
