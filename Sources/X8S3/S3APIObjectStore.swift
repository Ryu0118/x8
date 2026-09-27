#if X8_S3
    import X8Storage

    /// Binds an `S3ObjectClient` to the configured bucket for signed S3 API calls.
    ///
    /// Writes, administration, retention, and API-path reads share this one
    /// context so no call site can pair a client with a different bucket.
    package struct S3APIObjectStore: Sendable {
        /// The signed provider client.
        package let client: any S3ObjectClient

        /// The bucket containing X8 records.
        package let bucket: String

        /// Creates a store for one bucket.
        package init(client: any S3ObjectClient, bucket: String) {
            self.client = client
            self.bucket = bucket
        }

        /// Reads an object, or a byte range of it, returning `nil` when absent.
        package func get(key: String, byteRange: ClosedRange<Int64>? = nil) async throws -> ByteStream? {
            try await client.get(bucket: bucket, key: key, byteRange: byteRange)
        }

        /// Replaces an object with the supplied stream.
        package func put(key: String, body: ByteStream, contentLength: Int64?) async throws {
            try await client.put(bucket: bucket, key: key, body: body, contentLength: contentLength)
        }

        /// Lists object metadata below a prefix.
        package func list(prefix: String) async throws -> [S3ObjectMetadata] {
            try await client.list(bucket: bucket, prefix: prefix)
        }

        /// Deletes an object only when its provider revision still matches.
        package func delete(key: String, revision: String?) async throws -> S3DeleteResult {
            try await client.delete(bucket: bucket, key: key, revision: revision)
        }

        /// Deletes one provider-sized batch of objects.
        package func deleteObjects(_ objects: [S3ObjectDeletion]) async throws -> S3BatchDeleteResult {
            try await client.deleteObjects(bucket: bucket, objects: objects)
        }
    }

    extension S3APIObjectStore: S3ObjectReader {
        /// Reads a whole object through the signed API; the namespace needs no special handling.
        package func get(key: String, kind _: CacheObjectKind) async throws -> ByteStream? {
            try await get(key: key)
        }
    }
#endif
