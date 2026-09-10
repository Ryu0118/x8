import Foundation
import X8Core
import X8Storage

/// Shares forwarding behavior while test types expose different capabilities.
protocol ForwardingTestStorage: CASStore, ActionCacheStore {
    var data: InMemoryStorage { get }
}

extension ForwardingTestStorage {
    func get(id: CASDataID) async throws -> CASObject? {
        try await data.get(id: id)
    }

    func put(_ object: CASObject) async throws -> CASDataID {
        try await data.put(object)
    }

    func load(id: CASDataID) async throws -> ByteStream? {
        try await data.load(id: id)
    }

    func save(_ bytes: ByteStream) async throws -> CASDataID {
        try await data.save(bytes)
    }

    func getValue(for key: ActionCacheKey) async throws -> ActionCacheValue? {
        try await data.getValue(for: key)
    }

    func putValue(_ value: ActionCacheValue, for key: ActionCacheKey) async throws {
        try await data.putValue(value, for: key)
    }
}

struct DataOnlyTestStorage: ForwardingTestStorage {
    let data = InMemoryStorage()
}

struct AgeManagedTestStorage: ForwardingTestStorage, CacheAdministration {
    let data = InMemoryStorage()
    let recorder: CLIRecorder

    func listObjects(of kind: CacheObjectKind) async throws -> [CacheObject] {
        recorder.record("list")
        return [CacheObject(
            key: "old-object", kind: kind, identifier: Data([1]),
            modifiedAt: Date(timeIntervalSince1970: 0), byteCount: 1,
            revision: StorageRevision(rawValue: Data([2]))
        )]
    }

    func delete(_ object: CacheObject) async throws -> CacheDeleteResult {
        recorder.record("delete:\(object.key)")
        return .revisionChanged
    }

    func delete(_ objects: [CacheObject]) async throws -> CacheBatchDeleteResult {
        for object in objects {
            recorder.record("delete:\(object.key)")
        }
        return CacheBatchDeleteResult(deletedCount: 0, skippedCount: objects.count, failures: [])
    }
}
