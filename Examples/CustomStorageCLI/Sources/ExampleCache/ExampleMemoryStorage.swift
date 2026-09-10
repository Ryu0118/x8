import Foundation
import X8Core
import X8Storage

/// A bounded, non-persistent demonstration store; never use it as a remote cache.
actor ExampleMemoryStorage: CASStore, ActionCacheStore {
    private static let maximumRecords = 128
    private static let maximumPayloadBytes = 1_048_576
    private static let maximumMetadataEntries = 1024
    private var objects: [CASDataID: Record] = [:]
    private var actions: [ActionCacheKey: ActionCacheValue] = [:]

    func get(id: CASDataID) async throws -> CASObject? {
        try Task.checkCancellation()
        guard let record = objects[id] else { return nil }
        return CASObject(bytes: Self.stream(record.bytes), references: record.references)
    }

    func put(_ object: CASObject) async throws -> CASDataID {
        let bytes = try await Self.collect(object.bytes)
        guard objects.count < Self.maximumRecords,
              object.references.count <= Self.maximumMetadataEntries
        else { throw CapacityError.full }
        let id = CASDataID(rawValue: Data(UUID().uuidString.utf8))
        objects[id] = Record(bytes: bytes, references: object.references)
        return id
    }

    func load(id: CASDataID) async throws -> ByteStream? {
        try await get(id: id)?.bytes
    }

    func save(_ bytes: ByteStream) async throws -> CASDataID {
        try await put(CASObject(bytes: bytes, references: []))
    }

    func getValue(for key: ActionCacheKey) async throws -> ActionCacheValue? {
        try Task.checkCancellation()
        return actions[key]
    }

    func putValue(_ value: ActionCacheValue, for key: ActionCacheKey) async throws {
        try Task.checkCancellation()
        guard actions[key] != nil || actions.count < Self.maximumRecords else { throw CapacityError.full }
        guard value.entries.count <= Self.maximumMetadataEntries,
              value.entries.reduce(key.rawValue.count, { $0 + $1.key.utf8.count + $1.value.count }) <= Self.maximumPayloadBytes
        else { throw CapacityError.full }
        actions[key] = value
    }

    private struct Record {
        let bytes: Data
        let references: [CASDataID]
    }

    private enum CapacityError: Error {
        case full
    }

    private static func stream(_ bytes: Data) -> ByteStream {
        ByteStream(AsyncStream { continuation in
            continuation.yield(bytes)
            continuation.finish()
        })
    }

    private static func collect(_ stream: ByteStream) async throws -> Data {
        var bytes = Data()
        for try await chunk in stream {
            try Task.checkCancellation()
            guard chunk.count <= maximumPayloadBytes - bytes.count else { throw CapacityError.full }
            bytes.append(chunk)
        }
        try Task.checkCancellation()
        return bytes
    }
}
