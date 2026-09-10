#if X8_S3
    import AsyncOperations
    import Foundation
    import Testing
    @testable import X8S3

    @Suite("AsyncSemaphore bounds concurrency without leaking permits")
    struct AsyncSemaphoreTests {
        @Test
        func neverExceedsTheConfiguredLimit() async throws {
            let semaphore = AsyncSemaphore(limit: 3)
            let tracker = ConcurrencyTracker()

            try await Array(0 ..< 20).asyncForEach(numberOfConcurrentTasks: 20) { _ in
                try await semaphore.withPermit {
                    await tracker.enter()
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    await tracker.exit()
                }
            }

            #expect(await tracker.maximumObserved <= 3)
        }

        @Test
        func cancellationDoesNotLeakAPermit() async throws {
            let semaphore = AsyncSemaphore(limit: 1)
            let holderReleased = Gate()

            let holder = Task {
                try await semaphore.withPermit {
                    await holderReleased.wait()
                }
            }
            try await Task.sleep(nanoseconds: 10_000_000)

            let waiter = Task {
                try await semaphore.withPermit {}
            }
            try await Task.sleep(nanoseconds: 10_000_000)
            waiter.cancel()
            await holderReleased.open()
            _ = try await holder.value

            // A fresh acquire must still succeed: the cancelled waiter's
            // slot was never granted, so no permit was lost.
            try await semaphore.withPermit {}
        }
    }

    private actor ConcurrencyTracker {
        private var current = 0
        private(set) var maximumObserved = 0

        func enter() {
            current += 1
            maximumObserved = max(maximumObserved, current)
        }

        func exit() {
            current -= 1
        }
    }
#endif
