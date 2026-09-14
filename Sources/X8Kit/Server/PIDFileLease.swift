import Foundation
import Synchronization
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// Holds an exclusive, kernel-enforced claim on a detached server's pidfile.
///
/// `open(O_CREAT | O_EXLOCK | O_NONBLOCK)` atomically creates the file and
/// takes an exclusive `flock` in one syscall, so two runners racing to start
/// the same profile cannot both believe they own it — the loser's `open`
/// fails with `EWOULDBLOCK` rather than succeeding and requiring a
/// liveness-probe-and-retry dance. The kernel releases the lock the moment
/// this process exits for any reason, including a crash, which is exactly
/// the liveness signal a stale pidfile needs: a lock held means alive, a
/// claimable lock means the previous holder is gone. This makes reading and
/// interpreting the file's contents unnecessary for staleness detection.
package final class PIDFileLease: Sendable {
    private let fileDescriptor: Int32
    private let url: URL
    private let releaseState: Mutex<Bool>

    /// Attempts to claim `url`. Returns `nil` if another live process holds it.
    ///
    /// - Throws: If opening the file fails for a reason other than an
    ///   existing exclusive lock (for example, a permissions or path error).
    package static func claim(at url: URL, record: XcodeServeProcessRecord) throws -> PIDFileLease? {
        let descriptor = url.path.withCString { path in
            open(path, O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK, 0o600)
        }
        if descriptor < 0 {
            let code = errno
            guard code == EWOULDBLOCK || code == EAGAIN else {
                throw PIDFileLeaseError.openFailed(errno: code)
            }
            return nil
        }
        let lease = PIDFileLease(fileDescriptor: descriptor, url: url)
        do {
            try lease.write(record)
        } catch {
            lease.release()
            throw error
        }
        return lease
    }

    /// Removes the pidfile and releases the lock, in that order.
    ///
    /// Unlinking before closing means a concurrent claimant blocked on the
    /// same path can immediately create and lock a fresh inode once this
    /// descriptor closes, rather than momentarily seeing a lockable stale
    /// path point at this lease's already-doomed file.
    ///
    /// Idempotent: `XcodeCacheServerSession` reaches this from `wait()`,
    /// `shutdown()`, and `deinit`'s cleanup task, mirroring the existing
    /// (already-idempotent) socket removal on the same object. A second
    /// `close()` on this descriptor would otherwise target whatever fd
    /// number the kernel has since reused, corrupting an unrelated
    /// resource, so only the first caller actually closes it.
    package func release() {
        let shouldRelease = releaseState.withLock { alreadyReleased in
            defer { alreadyReleased = true }
            return !alreadyReleased
        }
        guard shouldRelease else { return }
        try? FileManager.default.removeItem(at: url)
        close(fileDescriptor)
    }

    private init(fileDescriptor: Int32, url: URL) {
        self.fileDescriptor = fileDescriptor
        self.url = url
        releaseState = Mutex(false)
    }

    private func write(_ record: XcodeServeProcessRecord) throws {
        let data = try JSONEncoder().encode(record)
        guard ftruncate(fileDescriptor, 0) == 0 else {
            throw PIDFileLeaseError.writeFailed(errno: errno)
        }
        try data.withUnsafeBytes { buffer in
            guard pwrite(fileDescriptor, buffer.baseAddress, buffer.count, 0) == buffer.count else {
                throw PIDFileLeaseError.writeFailed(errno: errno)
            }
        }
    }
}

/// Errors raised while claiming or writing a detached server's pidfile lease.
package enum PIDFileLeaseError: Error, Equatable {
    /// `open` failed for a reason other than the lock already being held.
    case openFailed(errno: Int32)
    /// Writing the process record into the claimed file failed.
    case writeFailed(errno: Int32)
}
