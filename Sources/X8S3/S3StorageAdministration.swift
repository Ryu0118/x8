#if X8_S3
    import AsyncOperations
    import Foundation
    import X8Core
    import X8Storage

    extension S3Storage: CacheAdministration, CASReferenceReader {
        /// Lists one X8 cache namespace as revision-bearing observations.
        public func listObjects(of kind: CacheObjectKind) async throws -> [CacheObject] {
            let metadata = try await requiredAPI(for: "Cache administration").list(prefix: keySpace.prefix(for: kind))
            // Provider listings can contain unrelated keys; only exact, parseable X8 keys become purge candidates.
            return metadata.compactMap { object in
                guard let identifier = keySpace.identifier(
                    from: object.key,
                    for: kind
                ) else {
                    return nil
                }
                return CacheObject(
                    key: object.key,
                    kind: kind,
                    identifier: identifier,
                    modifiedAt: object.modifiedAt,
                    byteCount: object.byteCount,
                    revision: object.revision.map(\.storageRevision)
                )
            }
        }

        /// Deletes one object only when its observed S3 revision still matches.
        ///
        /// A missing revision, mismatched key layout, missing object, or changed
        /// ETag is treated as a safe non-deletion result rather than a blind
        /// delete.
        public func delete(_ object: CacheObject) async throws -> CacheDeleteResult {
            guard let revision = object.revision else { return .revisionChanged }
            guard keySpace.matches(object) else {
                return .revisionChanged
            }
            let result = try await requiredAPI(for: "Cache administration").delete(
                key: object.key,
                revision: String(decoding: revision.rawValue, as: UTF8.self)
            )
            return result.cacheDeleteResult
        }

        /// Deletes many objects through provider-sized `DeleteObjects` batches.
        ///
        /// Objects with a mismatched key or missing revision are counted as
        /// skipped up front, the same as the single-object `delete(_:)`
        /// would report. The rest are chunked to the provider's per-request
        /// key limit and sent through a few concurrent requests, since R2 is
        /// confirmed to ignore each request's per-object revision
        /// precondition (see `X8S3.docc`); a changed object can therefore be
        /// deleted between this call's chunking and the request landing,
        /// same as any other race documented for this operation.
        public func delete(_ objects: [CacheObject]) async throws -> CacheBatchDeleteResult {
            let verified = objects.compactMap(deletionCandidate(for:))
            let preSkippedCount = objects.count - verified.count

            let chunks = verified.chunked(by: S3BatchDeleteLimits.maximumKeysPerRequest)
            let batchResults = try await chunks.asyncMap(
                numberOfConcurrentTasks: UInt(max(1, chunks.count))
            ) { chunk in
                try await self.requiredAPI(for: "Cache administration").deleteObjects(chunk)
            }

            let deletedCount = batchResults.reduce(0) { $0 + $1.deletedKeys.count }
            let failures = batchResults.flatMap(\.failures).map {
                CacheDeleteFailure(key: $0.key, reason: $0.code ?? $0.message ?? "unknown")
            }
            return CacheBatchDeleteResult(
                deletedCount: deletedCount,
                skippedCount: preSkippedCount,
                failures: failures
            )
        }

        /// Reads only the reference list from one CAS object.
        ///
        /// Requests only the first `S3StorageCodec.recommendedHeaderReadBytes`
        /// of the object via a ranged GET, so a full reachability traversal
        /// does not transfer entire payloads it never needs. Most objects'
        /// references fit within that bound; this falls back to a full read
        /// via `getCASRecord` both when the ranged read returns exactly that
        /// many bytes (the header may extend past what was requested from a
        /// Range-honoring provider) and when a Range-ignoring provider
        /// returns the whole object and the header decode consumes more than
        /// the requested bound. Either signal must fall back rather than
        /// surface as a remote error, since the object genuinely exists.
        public func references(of id: CASDataID) async throws -> [CASDataID]? {
            let range = Int64.zero ... (S3StorageCodec.recommendedHeaderReadBytes - 1)
            guard let stream = try await requiredAPI(for: "Cache administration").get(
                key: keySpace.cas(id: id.rawValue),
                byteRange: range
            ) else { return nil }

            let (prefix, exceededLimit, remainder) = try await ByteStreamSupport.collectPrefix(
                stream,
                maximumBytes: Int(S3StorageCodec.recommendedHeaderReadBytes)
            )
            guard !exceededLimit else {
                try await ByteStreamSupport.discard(remainder)
                return try await referencesFromFullRecord(id: id)
            }
            guard prefix.count < S3StorageCodec.recommendedHeaderReadBytes else {
                return try await referencesFromFullRecord(id: id)
            }

            let record = try S3StorageCodec.decodeCAS(prefix)
            return record.references
        }

        /// Converts one object to a batch-delete candidate, or nil when it has
        /// no revision or its key does not match this backend's layout.
        private func deletionCandidate(for object: CacheObject) -> S3ObjectDeletion? {
            guard let revision = object.revision, keySpace.matches(object) else { return nil }
            return S3ObjectDeletion(key: object.key, revision: String(decoding: revision.rawValue, as: UTF8.self))
        }

        /// Falls back to a full read when the ranged header prefix may be truncated.
        private func referencesFromFullRecord(id: CASDataID) async throws -> [CASDataID]? {
            guard let record = try await getCASRecord(
                id: id,
                via: requiredAPI(for: "Cache administration")
            ) else { return nil }
            try await ByteStreamSupport.discard(record.bytes)
            return record.references
        }
    }

    private extension String {
        var storageRevision: StorageRevision {
            StorageRevision(rawValue: Data(utf8))
        }
    }

    private extension Array {
        /// Splits into consecutive slices of at most `size` elements each.
        func chunked(by size: Int) -> [[Element]] {
            stride(from: 0, to: count, by: size).map {
                Array(self[$0 ..< Swift.min($0 + size, count)])
            }
        }
    }
#endif
