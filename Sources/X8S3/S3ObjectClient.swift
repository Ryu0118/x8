#if X8_S3
    import Foundation
    import SotoS3
    import X8Storage

    /// Provider metadata observed while listing one object namespace.
    ///
    /// The revision is carried alongside the listing so administrative callers
    /// can perform an optimistic-concurrency delete instead of deleting a key
    /// based on stale metadata.
    package struct S3ObjectMetadata: Sendable {
        /// The provider object key.
        package let key: String

        /// The provider's last-modified timestamp, when available.
        package let modifiedAt: Date?

        /// The object size, when available.
        package let byteCount: Int64?

        /// The provider revision used for conditional deletion.
        package let revision: String?
    }

    /// The result of a provider-level conditional delete.
    ///
    /// `revisionChanged` is a safe race outcome: the key may still exist, but
    /// the object observed by the caller is no longer the current object.
    package enum S3DeleteResult: Sendable {
        /// The object was deleted at the supplied revision.
        case deleted

        /// The object did not exist.
        case notFound

        /// The object no longer has the supplied revision.
        case revisionChanged
    }

    extension S3DeleteResult {
        var cacheDeleteResult: CacheDeleteResult {
            switch self {
            case .deleted:
                .deleted
            case .notFound:
                .notFound
            case .revisionChanged:
                .revisionChanged
            }
        }
    }

    /// One object to include in a batch delete request.
    package struct S3ObjectDeletion: Sendable {
        /// The provider key to delete.
        package let key: String

        /// The observed revision, sent as a precondition where the provider enforces one.
        package let revision: String?

        /// Creates a batch-delete entry.
        package init(key: String, revision: String?) {
            self.key = key
            self.revision = revision
        }
    }

    /// One object a batch delete request failed to remove, with an opaque provider reason.
    package struct S3BatchDeleteFailure: Sendable {
        /// The key that failed to delete.
        package let key: String

        /// The provider error code, when the response supplied one.
        package let code: String?

        /// A human-readable provider message, kept for diagnostics only.
        package let message: String?

        /// Creates a batch-delete failure.
        package init(key: String, code: String?, message: String?) {
            self.key = key
            self.code = code
            self.message = message
        }
    }

    /// The result of one batch delete request.
    ///
    /// `deletedKeys` is every input key the provider did not report as failed;
    /// a provider that reports an absent key as deleted is trusted, matching
    /// the single-object path's "absent is a safe outcome" rule.
    package struct S3BatchDeleteResult: Sendable {
        /// The keys the provider did not report as failed.
        package let deletedKeys: [String]

        /// The keys the provider reported as failed, with an opaque reason.
        package let failures: [S3BatchDeleteFailure]

        /// Creates a batch-delete result.
        package init(deletedKeys: [String], failures: [S3BatchDeleteFailure]) {
            self.deletedKeys = deletedKeys
            self.failures = failures
        }
    }

    /// Provider limits a batch delete request must respect.
    package enum S3BatchDeleteLimits {
        /// The maximum number of keys S3's `DeleteObjects` accepts per request.
        package static let maximumKeysPerRequest = 1000
    }

    /// The provider-neutral object operations required by `S3Storage`.
    ///
    /// This boundary deliberately exposes object bytes and provider revisions,
    /// but not Soto request types or X8 cache keys. `get` uses `nil` for a
    /// missing object, `list` returns the complete result below a prefix, and
    /// `delete` must enforce the supplied revision at the provider.
    package protocol S3ObjectClient: Sendable {
        /// Reads an object, returning `nil` when it does not exist.
        ///
        /// - Parameter byteRange: When supplied, requests only that inclusive
        ///   byte range (`Range: bytes=start-end`) instead of the whole
        ///   object. A provider may still return the complete object; callers
        ///   that need only a bounded prefix must be able to fall back to a
        ///   full read if the returned stream is shorter than expected.
        func get(bucket: String, key: String, byteRange: ClosedRange<Int64>?) async throws -> ByteStream?

        /// Replaces an object with the supplied stream.
        func put(bucket: String, key: String, body: ByteStream, contentLength: Int64?) async throws

        /// Lists object metadata below a provider prefix.
        func list(bucket: String, prefix: String) async throws -> [S3ObjectMetadata]

        /// Deletes an object only when its provider revision still matches.
        func delete(bucket: String, key: String, revision: String?) async throws -> S3DeleteResult

        /// Deletes up to `S3BatchDeleteLimits.maximumKeysPerRequest` keys in one request.
        ///
        /// A precondition (revision) is sent per key where the caller supplies
        /// one, but the provider may or may not enforce it; callers must treat
        /// this as best-effort, not a guaranteed conditional delete.
        func deleteObjects(bucket: String, objects: [S3ObjectDeletion]) async throws -> S3BatchDeleteResult
    }

    package extension S3ObjectClient {
        /// Reads a complete object; equivalent to `get(bucket:key:byteRange:)` with no range.
        func get(bucket: String, key: String) async throws -> ByteStream? {
            try await get(bucket: bucket, key: key, byteRange: nil)
        }
    }

    /// Adapts Soto's S3 service to the provider-neutral object boundary.
    ///
    /// The adapter translates not-found and failed-precondition responses,
    /// follows all list continuation pages, and leaves X8 key construction,
    /// envelope encoding, and purge policy to higher layers.
    package struct SotoS3ObjectClient: S3ObjectClient, Sendable {
        private let service: S3

        /// Creates an adapter around an initialized Soto service.
        package init(service: S3) {
            self.service = service
        }

        /// Reads an object, translating S3 not-found errors to `nil`.
        ///
        /// A supplied `byteRange` is sent as an HTTP `Range` header so the
        /// provider transfers only that span, not the whole object.
        package func get(
            bucket: String,
            key: String,
            byteRange: ClosedRange<Int64>?
        ) async throws -> ByteStream? {
            do {
                let output = try await service.getObject(
                    .init(bucket: bucket, key: key, range: byteRange.map(Self.rangeHeader))
                )
                return Self.stream(from: output.body)
            } catch let error as any AWSErrorType where Self.isNotFound(error) {
                return nil
            }
        }

        /// Uploads an object without applying provider-specific metadata.
        package func put(
            bucket: String,
            key: String,
            body: ByteStream,
            contentLength: Int64?
        ) async throws {
            let bodyLength = try Self.bodyLength(from: contentLength)
            _ = try await service.putObject(
                .init(
                    body: .init(asyncSequence: body, length: bodyLength),
                    bucket: bucket,
                    contentLength: contentLength,
                    key: key
                )
            )
        }

        /// Lists all objects below a prefix, following continuation tokens.
        package func list(bucket: String, prefix: String) async throws -> [S3ObjectMetadata] {
            var result: [S3ObjectMetadata] = []
            var continuationToken: String?
            var isComplete = false

            while !isComplete {
                let output = try await service.listObjectsV2(
                    .init(
                        bucket: bucket,
                        continuationToken: continuationToken,
                        prefix: prefix
                    )
                )
                result.append(contentsOf: (output.contents ?? []).compactMap(Self.metadata))

                // The provider's truncation flag is the completion signal; a stray token on a complete page is ignored.
                let nextToken = try Self.nextContinuationToken(
                    isTruncated: output.isTruncated,
                    nextToken: output.nextContinuationToken,
                    currentToken: continuationToken
                )
                isComplete = nextToken == nil
                continuationToken = nextToken
            }
            return result
        }

        /// Performs an S3 `If-Match` delete and classifies safe races.
        package func delete(
            bucket: String,
            key: String,
            revision: String?
        ) async throws -> S3DeleteResult {
            guard let revision else { return .revisionChanged }

            do {
                _ = try await service.deleteObject(
                    .init(bucket: bucket, ifMatch: revision, key: key)
                )
                return .deleted
            } catch let error as any AWSErrorType where Self.isNotFound(error) {
                return .notFound
            } catch let error as any AWSErrorType where Self.isRevisionChanged(error) {
                return .revisionChanged
            }
        }

        /// Deletes up to 1,000 keys in one `DeleteObjects` request.
        ///
        /// Quiet mode is used so the response lists only failures; every input
        /// key not reported as failed is treated as deleted, matching S3's own
        /// behavior of reporting an already-absent key as a successful delete.
        package func deleteObjects(
            bucket: String,
            objects: [S3ObjectDeletion]
        ) async throws -> S3BatchDeleteResult {
            precondition(
                objects.count <= S3BatchDeleteLimits.maximumKeysPerRequest,
                "deleteObjects received \(objects.count) keys; callers must chunk to \(S3BatchDeleteLimits.maximumKeysPerRequest)."
            )
            let output = try await service.deleteObjects(
                bucket: bucket,
                delete: .init(
                    objects: objects.map { .init(eTag: $0.revision, key: $0.key) },
                    quiet: true
                )
            )
            let failedKeys = Set((output.errors ?? []).compactMap(\.key))
            let deletedKeys = objects.map(\.key).filter { !failedKeys.contains($0) }
            let failures = (output.errors ?? []).compactMap { error -> S3BatchDeleteFailure? in
                guard let key = error.key else { return nil }
                return S3BatchDeleteFailure(key: key, code: error.code, message: error.message)
            }
            return S3BatchDeleteResult(deletedKeys: deletedKeys, failures: failures)
        }

        private static func rangeHeader(_ range: ClosedRange<Int64>) -> String {
            "bytes=\(range.lowerBound)-\(range.upperBound)"
        }

        private static func stream(from body: AWSHTTPBody) -> ByteStream {
            ByteStream(body.map { Data($0.readableBytesView) })
        }

        private static func metadata(from object: S3.Object) -> S3ObjectMetadata? {
            guard let key = object.key else { return nil }
            return S3ObjectMetadata(
                key: key,
                modifiedAt: object.lastModified,
                byteCount: object.size,
                revision: object.eTag
            )
        }

        private static func isNotFound(_ error: any AWSErrorType) -> Bool {
            error.errorCode == "NoSuchKey" || error.errorCode == "NotFound"
        }

        private static func isRevisionChanged(_ error: any AWSErrorType) -> Bool {
            error.errorCode == "PreconditionFailed"
                || error.context?.responseCode.code == 412
        }

        private static func nextContinuationToken(
            isTruncated: Bool?,
            nextToken: String?,
            currentToken: String?
        ) throws -> String? {
            guard isTruncated == true else { return nil }
            // A truncated page without a new token cannot make progress; fail instead of silently returning a partial scan.
            guard let nextToken,
                  !nextToken.isEmpty,
                  nextToken != currentToken
            else {
                throw S3ObjectClientError.invalidPagination
            }
            return nextToken
        }

        private static func bodyLength(from contentLength: Int64?) throws -> Int? {
            guard let contentLength else { return nil }
            guard contentLength >= 0, let bodyLength = Int(exactly: contentLength) else {
                throw S3ObjectClientError.invalidContentLength
            }
            return bodyLength
        }
    }

    private enum S3ObjectClientError: Error {
        case invalidContentLength
        case invalidPagination
    }
#endif
