#if X8_S3
    import Foundation
    import X8Core
    @testable import X8S3
    import X8Storage

    actor FakeS3ObjectClient: S3ObjectClient {
        private struct StoredObject: Sendable {
            let chunks: [Data]
            let modifiedAt: Date
            let revision: String
        }

        private var objects: [String: StoredObject] = [:]
        private(set) var putCallCount = 0
        private(set) var deleteObjectsCallCount = 0
        private(set) var deleteObjectsRequestSizes: [Int] = []
        private(set) var requestedByteRanges: [ClosedRange<Int64>?] = []
        private var putGate: Gate?
        /// Models Cloudflare R2's confirmed behavior: `DeleteObjects` deletes
        /// unconditionally and ignores any per-object revision precondition.
        /// Set to `false` to model a provider (like AWS S3) that honors it.
        var ignoresBatchPreconditions = true
        /// Models an S3-compatible provider that returns the whole object
        /// regardless of a requested `byteRange`, instead of honoring it.
        var ignoresByteRange = false
        /// Models a write-only credential that is denied `GetObject`.
        var deniesGets = false

        var objectCount: Int {
            objects.count
        }

        /// Makes every subsequent `put` suspend on `gate` before it stores
        /// the object, so a test can prove several concurrent callers were
        /// coalesced into a single in-flight upload.
        func gatePuts(on gate: Gate) {
            putGate = gate
        }

        /// Switches whether `deleteObjects` honors each entry's `revision`,
        /// modeling AWS S3 (`false`) instead of the default R2 behavior.
        func setIgnoresBatchPreconditions(_ value: Bool) {
            ignoresBatchPreconditions = value
        }

        /// Makes every `get` throw, modeling a credential without `GetObject`.
        func setDeniesGets(_ value: Bool) {
            deniesGets = value
        }

        /// Switches whether `get` honors a requested `byteRange`, modeling a
        /// Range-ignoring S3-compatible provider.
        func setIgnoresByteRange(_ value: Bool) {
            ignoresByteRange = value
        }

        func get(
            bucket: String,
            key: String,
            byteRange: ClosedRange<Int64>?
        ) async throws -> ByteStream? {
            requestedByteRanges.append(byteRange)
            guard !deniesGets else { throw FakeS3AccessDenied() }
            guard let object = objects["\(bucket)/\(key)"] else { return nil }
            guard let byteRange, !ignoresByteRange else {
                return TestByteStream.make(object.chunks)
            }
            let joined = Self.join(object.chunks)
            let lower = Int(byteRange.lowerBound)
            let upper = Swift.min(Int(byteRange.upperBound) + 1, joined.count)
            guard lower < upper else {
                return TestByteStream.make([])
            }
            return TestByteStream.make([joined.subdata(in: lower ..< upper)])
        }

        func put(
            bucket: String,
            key: String,
            body: ByteStream,
            contentLength _: Int64?
        ) async throws {
            putCallCount += 1
            if let putGate {
                await putGate.wait()
            }
            objects["\(bucket)/\(key)"] = try await StoredObject(
                chunks: [TestByteStream.collect(body)],
                modifiedAt: Date(),
                revision: UUID().uuidString
            )
        }

        func list(bucket: String, prefix: String) async throws -> [S3ObjectMetadata] {
            let bucketPrefix = "\(bucket)/\(prefix)"
            return objects.compactMap { key, object in
                guard key.hasPrefix(bucketPrefix) else { return nil }
                return S3ObjectMetadata(
                    key: String(key.dropFirst(bucket.count + 1)),
                    modifiedAt: object.modifiedAt,
                    byteCount: object.chunks.reduce(0) { $0 + Int64($1.count) },
                    revision: object.revision
                )
            }
            .sorted { $0.key < $1.key }
        }

        func delete(
            bucket: String,
            key: String,
            revision: String?
        ) async throws -> S3DeleteResult {
            let objectKey = "\(bucket)/\(key)"
            guard let object = objects[objectKey] else { return .notFound }
            guard object.revision == revision else { return .revisionChanged }
            objects.removeValue(forKey: objectKey)
            return .deleted
        }

        func deleteObjects(
            bucket: String,
            objects entries: [S3ObjectDeletion]
        ) async throws -> S3BatchDeleteResult {
            deleteObjectsCallCount += 1
            deleteObjectsRequestSizes.append(entries.count)
            let outcomes = entries.map { deleteOne(bucket: bucket, entry: $0) }
            let deletedKeys = zip(entries, outcomes).compactMap { entry, outcome in
                outcome.isDeleted ? entry.key : nil
            }
            let failures = outcomes.compactMap(\.failure)
            return S3BatchDeleteResult(deletedKeys: deletedKeys, failures: failures)
        }

        func value(for key: String) -> Data? {
            objects["foo/\(key)"].map { Self.join($0.chunks) }
        }

        func seed(
            _ chunks: [Data],
            for key: String,
            modifiedAt: Date = Date()
        ) {
            objects["foo/\(key)"] = StoredObject(
                chunks: chunks,
                modifiedAt: modifiedAt,
                revision: UUID().uuidString
            )
        }

        private static func join(_ chunks: [Data]) -> Data {
            chunks.reduce(into: Data()) { result, chunk in
                result.append(contentsOf: chunk)
            }
        }

        private enum BatchDeleteOutcome {
            case deleted
            case failed(S3BatchDeleteFailure)

            var isDeleted: Bool {
                if case .deleted = self {
                    return true
                }
                return false
            }

            var failure: S3BatchDeleteFailure? {
                guard case let .failed(failure) = self else { return nil }
                return failure
            }
        }

        /// Applies one batch-delete entry's precondition rule, mutating `objects` on success.
        private func deleteOne(bucket: String, entry: S3ObjectDeletion) -> BatchDeleteOutcome {
            let objectKey = "\(bucket)/\(entry.key)"
            guard let object = objects[objectKey] else { return .deleted }
            guard ignoresBatchPreconditions || object.revision == entry.revision else {
                return .failed(S3BatchDeleteFailure(key: entry.key, code: "PreconditionFailed", message: nil))
            }
            objects.removeValue(forKey: objectKey)
            return .deleted
        }
    }

    /// Lets a test suspend concurrent async work until it explicitly opens
    /// the gate, so it can prove a set of callers were still in flight
    /// together before releasing them.
    actor Gate {
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

    struct FakeS3AccessDenied: Error {}

    enum TestByteStream {
        static func make(_ chunks: [Data]) -> ByteStream {
            let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(
                of: Data.self
            )
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
            return ByteStream(stream)
        }

        static func collect(_ stream: ByteStream) async throws -> Data {
            var data = Data()
            for try await chunk in stream {
                data.append(contentsOf: chunk)
            }
            return data
        }
    }

    extension Data {
        var hexString: String {
            map { String(format: "%02x", $0) }.joined()
        }
    }
#endif
