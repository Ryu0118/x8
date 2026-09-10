import Foundation
import X8Core

/// An actor-isolated, non-persistent implementation of the cache contracts.
///
/// `InMemoryStorage` combines the data-plane, administration, and retention
/// capabilities so tests can exercise a complete cache domain without a
/// network or filesystem. Its state is protected by actor isolation; CAS
/// payloads and Action Cache values disappear when the actor is released. Its
/// deterministic generated IDs and revisions are backend-local opaque values
/// and do not define Xcode's identifier encoding or a remote provider's
/// concurrency token.
package actor InMemoryStorage: CASStore, ActionCacheStore, CacheAdministration, CASReferenceReader, CASRetentionStore {
    private struct StoredObject: Sendable {
        let bytes: Data
        let references: [CASDataID]
        let modifiedAt: Date
        let revision: StorageRevision
    }

    private struct StoredAction: Sendable {
        let value: ActionCacheValue
        let modifiedAt: Date
        let revision: StorageRevision
    }

    private var records: [CASDataID: StoredObject] = [:]
    private var actionValues: [ActionCacheKey: StoredAction] = [:]
    private var retentionAnchors: [Data: CASRetentionAnchor] = [:]

    /// Creates an empty in-memory storage instance.
    package init() {}

    /// Returns a record with payload and references, or `nil` when missing.
    package func get(id: CASDataID) async throws -> CASObject? {
        try Task.checkCancellation()
        guard let object = records[id] else { return nil }

        return CASObject(
            bytes: ByteStreamSupport.make(object.bytes),
            references: object.references
        )
    }

    /// Stores a complete object and returns its opaque identifier.
    package func put(_ object: CASObject) async throws -> CASDataID {
        let references = object.references
        let bytes = try await ByteStreamSupport.collect(object.bytes)
        return try store(
            bytes: bytes,
            references: references,
            conflict: .conflictingCASObject
        )
    }

    /// Returns payload bytes for a record, or `nil` when missing.
    package func load(id: CASDataID) async throws -> ByteStream? {
        try Task.checkCancellation()
        guard let record = records[id] else { return nil }

        return ByteStreamSupport.make(record.bytes)
    }

    /// Stores blob bytes and returns their opaque identifier.
    package func save(_ bytes: ByteStream) async throws -> CASDataID {
        let bytes = try await ByteStreamSupport.collect(bytes)
        return try store(
            bytes: bytes,
            references: [],
            conflict: .conflictingCASBlob
        )
    }

    /// Returns the value for a key, or `nil` when the key is missing.
    package func getValue(for key: ActionCacheKey) async throws -> ActionCacheValue? {
        try Task.checkCancellation()
        return actionValues[key]?.value
    }

    /// Replaces the value associated with a key.
    package func putValue(_ value: ActionCacheValue, for key: ActionCacheKey) async throws {
        try Task.checkCancellation()
        actionValues[key] = StoredAction(
            value: value,
            modifiedAt: Date(),
            revision: newRevision()
        )
    }

    /// Lists in-memory administrative objects by cache namespace.
    package func listObjects(of kind: CacheObjectKind) async throws -> [CacheObject] {
        try Task.checkCancellation()
        return switch kind {
        case .staging:
            []
        case .actionCache:
            actionObjects()
        case .cas:
            casObjects()
        }
    }

    /// Deletes one in-memory object when its revision still matches.
    package func delete(_ object: CacheObject) async throws -> CacheDeleteResult {
        try Task.checkCancellation()
        return switch object.kind {
        case .staging:
            .notFound
        case .actionCache:
            deleteAction(object)
        case .cas:
            deleteCAS(object)
        }
    }

    /// Deletes many in-memory objects, applying the same revision rule as `delete(_:)` to each.
    package func delete(_ objects: [CacheObject]) async throws -> CacheBatchDeleteResult {
        try Task.checkCancellation()
        let results = try await objects.asyncMap { try await self.delete($0) }
        let deletedCount = results.count(where: { $0 == .deleted })
        return CacheBatchDeleteResult(
            deletedCount: deletedCount,
            skippedCount: objects.count - deletedCount,
            failures: []
        )
    }

    /// Returns only the references stored in a CAS record.
    package func references(of id: CASDataID) async throws -> [CASDataID]? {
        try Task.checkCancellation()
        return records[id]?.references
    }

    /// Returns all in-memory roots and leases as an authoritative snapshot.
    package func retentionSnapshot() async throws -> CASRetentionSnapshot {
        try Task.checkCancellation()
        return CASRetentionSnapshot(
            anchors: retentionAnchors.values.map(\.self),
            isAuthoritative: true
        )
    }

    /// Replaces or creates an in-memory root or lease.
    package func putRetentionAnchor(_ anchor: CASRetentionAnchor) async throws {
        try Task.checkCancellation()
        let revision = newRevision()
        let storedAnchor = CASRetentionAnchor(
            kind: anchor.kind,
            identifier: anchor.identifier,
            objectIDs: anchor.objectIDs,
            expiresAt: anchor.expiresAt,
            revision: revision
        )
        retentionAnchors[anchor.identifier] = storedAnchor
    }

    /// Removes an in-memory root or lease when its revision still matches.
    package func deleteRetentionAnchor(_ anchor: CASRetentionAnchor) async throws -> CacheDeleteResult {
        try Task.checkCancellation()
        guard let current = retentionAnchors[anchor.identifier] else {
            return .notFound
        }
        guard current.revision == anchor.revision else {
            return .revisionChanged
        }
        retentionAnchors.removeValue(forKey: anchor.identifier)
        return .deleted
    }

    private func store(
        bytes: Data,
        references: [CASDataID],
        conflict: StorageError.Kind
    ) throws -> CASDataID {
        // Callers materialize streams before this actor mutation so cancellation
        // or producer failure cannot publish a partial test record.
        let id = CASDataIDGenerator.id(for: bytes, references: references)

        guard let existing = records[id] else {
            records[id] = StoredObject(
                bytes: bytes,
                references: references,
                modifiedAt: Date(),
                revision: newRevision()
            )
            return id
        }
        guard existing.bytes == bytes, existing.references == references else {
            throw StorageError(kind: conflict, id: id)
        }
        return id
    }

    private func casObjects() -> [CacheObject] {
        records.map { id, object in
            CacheObject(
                key: casKey(for: id),
                kind: .cas,
                identifier: id.rawValue,
                modifiedAt: object.modifiedAt,
                byteCount: Int64(object.bytes.count),
                revision: object.revision
            )
        }
        .sorted { $0.key < $1.key }
    }

    private func actionObjects() -> [CacheObject] {
        actionValues.map { key, action in
            CacheObject(
                key: actionKey(for: key),
                kind: .actionCache,
                identifier: key.rawValue,
                modifiedAt: action.modifiedAt,
                byteCount: action.value.entries.reduce(into: Int64.zero) { total, entry in
                    total += Int64(entry.key.utf8.count + entry.value.count)
                },
                revision: action.revision
            )
        }
        .sorted { $0.key < $1.key }
    }

    private func deleteCAS(_ object: CacheObject) -> CacheDeleteResult {
        let id = CASDataID(rawValue: object.identifier)
        guard object.key == casKey(for: id) else { return .revisionChanged }
        guard let current = records[id] else { return .notFound }
        guard current.revision == object.revision else { return .revisionChanged }
        records.removeValue(forKey: id)
        return .deleted
    }

    private func deleteAction(_ object: CacheObject) -> CacheDeleteResult {
        let key = ActionCacheKey(rawValue: object.identifier)
        guard object.key == actionKey(for: key) else { return .revisionChanged }
        guard let current = actionValues[key] else { return .notFound }
        guard current.revision == object.revision else { return .revisionChanged }
        actionValues.removeValue(forKey: key)
        return .deleted
    }

    private func newRevision() -> StorageRevision {
        var uuid = UUID()
        return StorageRevision(rawValue: withUnsafeBytes(of: &uuid) { Data($0) })
    }

    private func casKey(for id: CASDataID) -> String {
        "cas/" + id.rawValue.hexString
    }

    private func actionKey(for key: ActionCacheKey) -> String {
        "action-cache/" + key.rawValue.hexString
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
