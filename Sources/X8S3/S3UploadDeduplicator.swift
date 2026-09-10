#if X8_S3
    import Foundation

    /// De-duplicates concurrent and repeated uploads to the same logical key.
    ///
    /// R2 rejects more than one write per second to the same object key.
    /// Callers that have already succeeded for a key in this process never
    /// need to upload again, and callers racing to write the same key
    /// before either has recorded success are collapsed into one upload.
    /// Failures are never memoized: a failed upload must be fully retried
    /// by whichever caller observes the failure.
    package actor S3UploadDeduplicator<Key: Hashable & Sendable> {
        private enum State {
            case inFlight(Task<Void, any Error>)
            case succeeded(useOrder: UInt64)
        }

        private var states: [Key: State] = [:]
        private let capacity: Int
        /// Monotonically increasing use counter. Recording a use is O(1); it
        /// only assigns the next value rather than reordering a list, so
        /// eviction is the only operation that scans `states`, and it only
        /// runs once capacity is actually exceeded.
        private var nextUseOrder: UInt64 = 0

        /// Creates a deduplicator that remembers up to `capacity` successful
        /// keys, evicting the least-recently-used key once full.
        package init(capacity: Int = 100_000) {
            self.capacity = capacity
        }

        /// Runs `upload` for `key` at most once concurrently, and never
        /// again once it has already succeeded for this key.
        package func withDeduplication(
            key: Key,
            upload: @Sendable @escaping () async throws -> Void
        ) async throws {
            if case .succeeded = states[key] {
                return
            }
            if case let .inFlight(task) = states[key] {
                return try await task.value
            }

            let task = Task { try await upload() }
            states[key] = .inFlight(task)
            do {
                try await task.value
                recordUse(of: key)
            } catch {
                states[key] = nil
                throw error
            }
        }

        private func recordUse(of key: Key) {
            states[key] = .succeeded(useOrder: nextUseOrder)
            nextUseOrder += 1
            guard states.count > capacity else { return }
            evictLeastRecentlyUsed()
        }

        /// Scans every remembered succeeded key for the smallest use order.
        /// Runs only when `states.count` exceeds `capacity`, so this cost is
        /// paid at most once per `capacity` successful uploads, not on
        /// every use. An in-flight key is never a candidate: only a
        /// succeeded upload counts toward capacity.
        private func evictLeastRecentlyUsed() {
            let succeededOrders: [(key: Key, useOrder: UInt64)] = states.compactMap { key, state in
                guard case let .succeeded(useOrder) = state else { return nil }
                return (key, useOrder)
            }
            guard let oldest = succeededOrders.min(by: { $0.useOrder < $1.useOrder }) else { return }
            states[oldest.key] = nil
        }
    }
#endif
