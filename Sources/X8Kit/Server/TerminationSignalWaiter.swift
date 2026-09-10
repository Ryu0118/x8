import Darwin
import Dispatch
import Foundation

/// Waits for a process termination request without applying shutdown policy.
///
/// A caller decides whether a received signal should stop a server or perform
/// another cleanup action.
package protocol TerminationSignalWaiting: Sendable {
    /// Suspends until termination is requested or the waiting task is cancelled.
    ///
    /// Returns the received signal for `SIGINT`/`SIGTERM`, or `nil` when the
    /// waiting task is cancelled before a signal arrives.
    func wait() async -> TerminationSignal?
}

/// Identifies the process signal requested by a parent or supervisor.
package enum TerminationSignal: Sendable {
    /// An interactive interrupt, normally sent by Control-C.
    case interrupt

    /// A termination request from a supervisor or service manager.
    case terminate
}

/// Waits for process termination signals and restores prior signal handlers.
///
/// One wait installs temporary dispatch signal sources for `SIGINT` and
/// `SIGTERM`. The first signal or cancellation resumes the waiter, cancels the
/// sources, and restores the handlers that were active before the wait began.
/// It reports the event to its caller instead of terminating the process itself.
package final class TerminationSignalWaiter: TerminationSignalWaiting, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TerminationSignal?, Never>?
    private var sources: [DispatchSourceSignal] = []

    init() {}

    /// Waits for SIGINT or SIGTERM, returning early when the task is cancelled.
    package func wait() async -> TerminationSignal? {
        if Task.isCancelled {
            return nil
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                install(continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func install(_ continuation: CheckedContinuation<TerminationSignal?, Never>) {
        // Signal callbacks and cancellation can race, so the continuation and sources share one lock.
        lock.lock()
        // The unlocked check is a fast path; this locked check closes the cancellation-versus-install race.
        guard !Task.isCancelled else {
            lock.unlock()
            continuation.resume(returning: nil)
            return
        }
        self.continuation = continuation
        // Ignore default delivery while DispatchSource owns these signals, then restore each prior handler.
        for signalNumber in [SIGINT, SIGTERM] {
            let previousHandler = Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: DispatchQueue.global(qos: .userInitiated)
            )
            source.setEventHandler { [weak self] in
                self?.resume(with: Self.signal(for: signalNumber))
            }
            source.setCancelHandler {
                _ = Darwin.signal(signalNumber, previousHandler)
            }
            sources.append(source)
            source.resume()
        }
        lock.unlock()
    }

    private func cancel() {
        resume(with: nil)
    }

    private func resume(with signal: TerminationSignal?) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let sources = sources
        self.sources = []
        lock.unlock()

        // Clear state before cancelling sources so a concurrent callback cannot resume twice.
        sources.forEach { $0.cancel() }
        continuation.resume(returning: signal)
    }

    private static func signal(for signalNumber: Int32) -> TerminationSignal {
        signalNumber == SIGINT ? .interrupt : .terminate
    }
}
