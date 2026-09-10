#if X8_S3
    import AsyncOperations
    import Foundation
    import Testing
    @testable import X8S3

    @Suite("S3UploadDeduplicator coalesces and memoizes uploads by key")
    struct S3UploadDeduplicatorTests {
        @Test
        func skipsUploadOnceAKeyHasSucceeded() async throws {
            let deduplicator = S3UploadDeduplicator<String>()
            let callCount = Counter()

            try await deduplicator.withDeduplication(key: "a") { await callCount.increment() }
            try await deduplicator.withDeduplication(key: "a") { await callCount.increment() }

            #expect(await callCount.value == 1)
        }

        @Test
        func collapsesConcurrentCallersIntoOneUpload() async throws {
            let deduplicator = S3UploadDeduplicator<String>()
            let callCount = Counter()
            let gate = TestGate()

            let opener = Task {
                try? await Task.sleep(nanoseconds: 20_000_000)
                await gate.open()
            }
            try await Array(repeating: (), count: 10).asyncForEach(numberOfConcurrentTasks: 10) { _ in
                try await deduplicator.withDeduplication(key: "a") {
                    await callCount.increment()
                    await gate.wait()
                }
            }
            await opener.value

            #expect(await callCount.value == 1)
        }

        @Test
        func doesNotMemoizeFailures() async throws {
            let deduplicator = S3UploadDeduplicator<String>()
            let callCount = Counter()

            struct TestError: Error {}

            await #expect(throws: TestError.self) {
                try await deduplicator.withDeduplication(key: "a") {
                    await callCount.increment()
                    throw TestError()
                }
            }
            try await deduplicator.withDeduplication(key: "a") { await callCount.increment() }

            #expect(await callCount.value == 2)
        }

        @Test
        func evictsTheLeastRecentlyUsedKeyOnceOverCapacity() async throws {
            let deduplicator = S3UploadDeduplicator<String>(capacity: 2)
            let callCount = Counter()

            try await deduplicator.withDeduplication(key: "a") { await callCount.increment() }
            try await deduplicator.withDeduplication(key: "b") { await callCount.increment() }
            // "a" is now the least-recently used key; putting "c" evicts it.
            try await deduplicator.withDeduplication(key: "c") { await callCount.increment() }

            // "b" and "c" are still memoized; "a" was evicted and uploads again.
            try await deduplicator.withDeduplication(key: "b") { await callCount.increment() }
            try await deduplicator.withDeduplication(key: "c") { await callCount.increment() }
            try await deduplicator.withDeduplication(key: "a") { await callCount.increment() }

            #expect(await callCount.value == 4)
        }

        @Test
        func concurrentCallersAllObserveAFailure() async {
            let deduplicator = S3UploadDeduplicator<String>()
            let gate = TestGate()

            struct TestError: Error {}

            let opener = Task {
                try? await Task.sleep(nanoseconds: 20_000_000)
                await gate.open()
            }
            let failures = await Array(repeating: (), count: 5).asyncMap(numberOfConcurrentTasks: 5) { _ in
                do {
                    try await deduplicator.withDeduplication(key: "a") {
                        await gate.wait()
                        throw TestError()
                    }
                    return false
                } catch {
                    return true
                }
            }
            await opener.value
            #expect(failures.allSatisfy { $0 == true })
        }
    }

    private actor Counter {
        private(set) var value = 0
        func increment() {
            value += 1
        }
    }

    private actor TestGate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }

        func wait() async {
            if isOpen {
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
#endif
