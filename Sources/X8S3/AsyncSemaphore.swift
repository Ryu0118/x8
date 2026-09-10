#if X8_S3
    import Foundation

    /// A cooperative concurrency limiter for async work.
    ///
    /// Cancellation of a waiting task must not leak a permit slot or strand
    /// a continuation; `withTaskCancellationHandler` guarantees a waiter is
    /// either never enqueued or removed and resumed exactly once.
    package actor AsyncSemaphore {
        private var availablePermits: Int
        private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

        /// Creates a semaphore that allows up to `limit` concurrent holders.
        package init(limit: Int) {
            precondition(limit > 0, "AsyncSemaphore requires a positive limit")
            availablePermits = limit
        }

        /// Runs `operation` while holding one permit, waiting for one to
        /// become available first.
        package func withPermit<T: Sendable>(
            _ operation: @Sendable () async throws -> T
        ) async throws -> T {
            try await acquire()
            do {
                let result = try await operation()
                release()
                return result
            } catch {
                release()
                throw error
            }
        }

        private func acquire() async throws {
            if availablePermits > 0 {
                availablePermits -= 1
                return
            }
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append((id, continuation))
                }
            } onCancel: {
                Task { await self.cancelWaiter(id: id) }
            }
        }

        private func release() {
            if let next = waiters.first {
                waiters.removeFirst()
                next.continuation.resume()
            } else {
                availablePermits += 1
            }
        }

        private func cancelWaiter(id: UUID) {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
            let (_, continuation) = waiters.remove(at: index)
            continuation.resume(throwing: CancellationError())
        }
    }
#endif
