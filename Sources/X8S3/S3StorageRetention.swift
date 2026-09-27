#if X8_S3
    import AsyncOperations
    import Foundation
    import X8Core
    import X8Storage

    private struct RetentionDocument {
        let anchor: CASRetentionAnchor?
        let isValid: Bool

        static let ignored = Self(anchor: nil, isValid: true)
        static let invalid = Self(anchor: nil, isValid: false)

        static func valid(_ anchor: CASRetentionAnchor) -> Self {
            Self(anchor: anchor, isValid: true)
        }
    }

    extension S3Storage: CASRetentionStore {
        /// Matches `CachePurgePlanner.maximumConcurrentReads`, the same
        /// bound used for other administrative reachability reads.
        private static let maximumConcurrentReads = 32

        /// Reads X8-owned retention anchors and reports whether the namespace is authoritative.
        ///
        /// Authority requires valid, revision-bearing retention documents,
        /// plus either the explicit marker or an empty anchor set. An empty
        /// retention namespace is trivially complete: there is nothing an
        /// incomplete listing could have missed. A non-empty namespace
        /// without the marker means something other than `putRetentionAnchor`
        /// wrote into `retention/`, so it stays non-authoritative. The
        /// listing and subsequent reads are not atomic; without complete,
        /// valid observations, CAS purge must fail closed.
        public func retentionSnapshot() async throws -> CASRetentionSnapshot {
            let metadata = try await requiredAPI(for: .retention).list(prefix: keySpace.retentionPrefix)
            let markerKey = keySpace.authorityMarkerKey
            let hasAuthorityMarker = try await authorityMarkerExists(at: markerKey)
            let documents = try await retentionDocuments(
                metadata,
                excluding: markerKey
            )

            return CASRetentionSnapshot(
                anchors: documents.anchors,
                isAuthoritative: documents.areValid && (hasAuthorityMarker || documents.anchors.isEmpty)
            )
        }

        /// Stores an X8-owned root or lease and enables explicit retention authority.
        ///
        /// The anchor document and authority marker are kept in the retention
        /// namespace, separate from Action Cache and CAS objects.
        public func putRetentionAnchor(_ anchor: CASRetentionAnchor) async throws {
            let api = try requiredAPI(for: .retention)
            let data = try S3RetentionCodec.encode(anchor)
            let key = keySpace.retention(identifier: anchor.identifier)
            try await api.put(
                key: key,
                body: ByteStreamSupport.make(data),
                contentLength: Int64(data.count)
            )

            let markerKey = keySpace.authorityMarkerKey
            try await api.put(
                key: markerKey,
                body: ByteStreamSupport.make(S3RetentionCodec.authorityMarker),
                contentLength: Int64(S3RetentionCodec.authorityMarker.count)
            )
        }

        /// Deletes an X8-owned root or lease at its expected provider revision.
        ///
        /// A stale or missing revision is reported as a safe non-deletion result.
        public func deleteRetentionAnchor(
            _ anchor: CASRetentionAnchor
        ) async throws -> CacheDeleteResult {
            guard let revision = anchor.revision else { return .revisionChanged }
            let key = keySpace.retention(identifier: anchor.identifier)
            let result = try await requiredAPI(for: .retention).delete(
                key: key,
                revision: String(decoding: revision.rawValue, as: UTF8.self)
            )
            return result.cacheDeleteResult
        }

        /// Reads every retention document in `metadata` with up to
        /// `maximumConcurrentReads` requests in flight, matching
        /// `CachePurgePlanner`'s bounded-concurrency reads so this does not
        /// serialize into one request per anchor/lease on a large namespace.
        private func retentionDocuments(
            _ metadata: [S3ObjectMetadata],
            excluding markerKey: String
        ) async throws -> (anchors: [CASRetentionAnchor], areValid: Bool) {
            let documents = try await metadata.asyncMap(
                numberOfConcurrentTasks: UInt(Self.maximumConcurrentReads)
            ) { object in
                try await self.retentionDocument(for: object, excluding: markerKey)
            }
            // One malformed, missing, or concurrently changed document makes the listing incomplete.
            // Purge must fail closed rather than treating the remaining anchors as authoritative.
            let areValid = documents.allSatisfy(\.isValid)
            let anchors = documents.compactMap(\.anchor)
            return (anchors, areValid)
        }

        private func retentionDocument(
            for object: S3ObjectMetadata,
            excluding markerKey: String
        ) async throws -> RetentionDocument {
            guard object.key != markerKey else { return .ignored }
            guard let revision = object.revision else { return .invalid }
            guard let identifier = keySpace.retentionIdentifier(from: object.key) else {
                return .invalid
            }

            // Decode the bytes using the revision observed in the listing; a later conditional
            // delete still refuses to remove an anchor whose provider revision has changed.
            guard let data = try await objectData(
                at: object.key,
                maximumBytes: S3Storage.maximumBufferedObjectBytes
            ) else { return .invalid }
            guard let anchor = decodeRetentionAnchor(
                data,
                revision: revision,
                identifier: identifier
            ) else {
                return .invalid
            }
            return .valid(anchor)
        }

        private func decodeRetentionAnchor(
            _ data: Data,
            revision: String,
            identifier: Data
        ) -> CASRetentionAnchor? {
            // Malformed or raced documents are treated as invalid so purge fails closed.
            guard let anchor = try? S3RetentionCodec.decode(
                data,
                revision: StorageRevision(rawValue: Data(revision.utf8))
            ), anchor.identifier == identifier else {
                return nil
            }
            return anchor
        }

        private func authorityMarkerExists(at key: String) async throws -> Bool {
            guard let data = try await objectData(
                at: key,
                maximumBytes: S3RetentionCodec.authorityMarker.count
            ) else { return false }
            return data == S3RetentionCodec.authorityMarker
        }

        private func objectData(at key: String, maximumBytes: Int) async throws -> Data? {
            guard let stream = try await requiredAPI(for: .retention).get(key: key) else {
                return nil
            }
            return try await ByteStreamSupport.collect(
                stream,
                maximumBytes: maximumBytes
            )
        }
    }
#endif
