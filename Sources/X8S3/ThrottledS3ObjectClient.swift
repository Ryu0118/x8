#if X8_S3
    import X8Storage

    /// Wraps an `S3ObjectClient` with a global concurrency limit.
    ///
    /// A wide connection pool is only safe if the number of simultaneously
    /// in-flight requests is also bounded; otherwise the same
    /// deadline-exceeded failures reappear at a higher task count. This
    /// wrapper is provider-agnostic and applies uniformly to reads and
    /// writes.
    package struct ThrottledS3ObjectClient: S3ObjectClient {
        private let wrapped: any S3ObjectClient
        private let semaphore: AsyncSemaphore

        /// Wraps `client`, limiting it to `maximumConcurrentOperations` simultaneous requests.
        package init(wrapping client: any S3ObjectClient, maximumConcurrentOperations: Int) {
            wrapped = client
            semaphore = AsyncSemaphore(limit: maximumConcurrentOperations)
        }

        /// Reads an object through the wrapped client, honoring the concurrency limit.
        package func get(
            bucket: String,
            key: String,
            byteRange: ClosedRange<Int64>?
        ) async throws -> ByteStream? {
            try await semaphore.withPermit { try await wrapped.get(bucket: bucket, key: key, byteRange: byteRange) }
        }

        /// Replaces an object through the wrapped client, honoring the concurrency limit.
        package func put(
            bucket: String,
            key: String,
            body: ByteStream,
            contentLength: Int64?
        ) async throws {
            try await semaphore.withPermit {
                try await wrapped.put(bucket: bucket, key: key, body: body, contentLength: contentLength)
            }
        }

        /// Lists object metadata through the wrapped client, honoring the concurrency limit.
        package func list(bucket: String, prefix: String) async throws -> [S3ObjectMetadata] {
            try await semaphore.withPermit { try await wrapped.list(bucket: bucket, prefix: prefix) }
        }

        /// Deletes an object through the wrapped client, honoring the concurrency limit.
        package func delete(
            bucket: String,
            key: String,
            revision: String?
        ) async throws -> S3DeleteResult {
            try await semaphore.withPermit { try await wrapped.delete(bucket: bucket, key: key, revision: revision) }
        }

        /// Deletes many objects through the wrapped client, honoring the concurrency limit.
        ///
        /// One permit is held for the whole batch request, not per key: the
        /// limit bounds simultaneously in-flight *requests*, and a batch
        /// delete is one request regardless of how many keys it carries.
        package func deleteObjects(
            bucket: String,
            objects: [S3ObjectDeletion]
        ) async throws -> S3BatchDeleteResult {
            try await semaphore.withPermit { try await wrapped.deleteObjects(bucket: bucket, objects: objects) }
        }
    }
#endif
