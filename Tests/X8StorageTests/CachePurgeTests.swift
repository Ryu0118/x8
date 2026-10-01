import AsyncOperations
import Foundation
import Testing
import X8Core
@testable import X8Storage

@Suite("Cache purge safety")
struct CachePurgeTests {
    /// Treats `entries["value"]` as a bare `CASDataID`, standing in for the
    /// real protobuf-based extractor that lives in X8Kit (see
    /// `ActionCacheRootExtractor`); `X8Storage`'s tests only need the
    /// planner's contract with an injected root-extraction closure.
    private static let testRootExtractor: @Sendable (ActionCacheValue) throws -> [CASDataID]? = { value in
        guard let bytes = value.entries["value"] else { return nil }
        return [CASDataID(rawValue: bytes)]
    }

    @Test
    func ageBasedPlanSelectsOnlyOldObjects() async throws {
        let storage = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x01]))
        try await storage.putValue(
            ActionCacheValue(entries: ["value": Data([0x02])]),
            for: key
        )
        let service = CachePurgeService(administration: storage)
        let plan = try await service.plan(
            CachePurgeRequest(
                scope: .actionCache,
                now: Date().addingTimeInterval(60),
                olderThan: .seconds(30)
            )
        )

        #expect(plan.candidates.count == 1)
        #expect(plan.candidates[0].identifier == key.rawValue)
    }

    @Test
    func executeSkipsAnObjectChangedAfterPlanning() async throws {
        let storage = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x03]))
        try await storage.putValue(
            ActionCacheValue(entries: ["value": Data([0x04])]),
            for: key
        )
        let service = CachePurgeService(administration: storage)
        let plan = try await service.plan(
            CachePurgeRequest(
                scope: .actionCache,
                now: Date().addingTimeInterval(60),
                olderThan: .seconds(30)
            )
        )

        try await storage.putValue(
            ActionCacheValue(entries: ["value": Data([0x05])]),
            for: key
        )
        let result = try await service.execute(plan, confirm: true)

        #expect(result.deletedCount == 0)
        #expect(result.skippedCount == 1)
        #expect(try await storage.getValue(for: key) != nil)
    }

    @Test
    func casPlanKeepsReachableGraphAndSelectsOrphans() async throws {
        let storage = InMemoryStorage()
        let leaf = try await storage.save(ByteStreamSupport.make(Data([0x10])))
        let root = try await storage.put(
            CASObject(
                bytes: ByteStreamSupport.make(Data([0x11])),
                references: [leaf]
            )
        )
        let orphan = try await storage.save(ByteStreamSupport.make(Data([0x12])))
        try await storage.putValue(
            ActionCacheValue(entries: ["value": root.rawValue]),
            for: ActionCacheKey(rawValue: Data([0x50]))
        )

        let service = CachePurgeService(
            administration: storage,
            referenceReader: storage,
            retentionStore: storage,
            actionCacheStore: storage,
            actionCacheRootExtractor: Self.testRootExtractor
        )
        let plan = try await service.plan(
            CachePurgeRequest(
                scope: .cas,
                now: Date().addingTimeInterval(60),
                gracePeriod: .seconds(30)
            )
        )

        #expect(plan.candidates.map(\.identifier) == [orphan.rawValue])
    }

    @Test
    func casPlanRequiresExplicitAuthority() async throws {
        let storage = InMemoryStorage()
        let service = CachePurgeService(
            administration: storage,
            referenceReader: storage,
            retentionStore: NonAuthoritativeRetentionStore(),
            actionCacheStore: storage,
            actionCacheRootExtractor: Self.testRootExtractor
        )

        await #expect(throws: CachePurgeError.nonAuthoritativeRetention) {
            try await service.plan(
                CachePurgeRequest(scope: .cas, gracePeriod: .seconds(30))
            )
        }
    }

    @Test
    func casPlanRequiresAnActionCacheStore() async throws {
        let storage = InMemoryStorage()
        let service = CachePurgeService(
            administration: storage,
            referenceReader: storage,
            retentionStore: storage
        )

        await #expect(throws: CachePurgeError.actionCacheStoreUnavailable) {
            try await service.plan(
                CachePurgeRequest(scope: .cas, gracePeriod: .seconds(30))
            )
        }
    }

    @Test
    func expiredLeaseDoesNotKeepCASObjectReachable() async throws {
        let storage = InMemoryStorage()
        let now = Date()
        let root = try await storage.save(ByteStreamSupport.make(Data([0x21])))
        try await storage.putRetentionAnchor(
            CASRetentionAnchor(
                kind: .lease,
                identifier: Data([0x22]),
                objectIDs: [root],
                expiresAt: now.addingTimeInterval(-1),
                revision: nil
            )
        )
        let service = CachePurgeService(
            administration: storage,
            referenceReader: storage,
            retentionStore: storage,
            actionCacheStore: storage,
            actionCacheRootExtractor: Self.testRootExtractor
        )

        let plan = try await service.plan(
            CachePurgeRequest(
                scope: .cas,
                now: now.addingTimeInterval(60),
                gracePeriod: .seconds(30)
            )
        )

        #expect(plan.candidates.map(\.identifier) == [root.rawValue])
    }

    @Test
    func casPlanFailsWhenAReachableObjectIsMissing() async throws {
        let storage = InMemoryStorage()
        let missing = CASDataID(rawValue: Data([0x31]))
        try await storage.putRetentionAnchor(
            CASRetentionAnchor(
                kind: .root,
                identifier: Data([0x32]),
                objectIDs: [missing],
                expiresAt: nil,
                revision: nil
            )
        )
        let service = CachePurgeService(
            administration: storage,
            referenceReader: storage,
            retentionStore: storage,
            actionCacheStore: storage,
            actionCacheRootExtractor: Self.testRootExtractor
        )

        await #expect(throws: CachePurgeError.missingReferencedObject(missing)) {
            try await service.plan(
                CachePurgeRequest(scope: .cas, gracePeriod: .seconds(30))
            )
        }
    }

    @Test
    func casPlanTreatsADanglingActionCacheRootAsSafeToIgnore() async throws {
        let storage = InMemoryStorage()
        let orphan = try await storage.save(ByteStreamSupport.make(Data([0x60])))
        let missingRoot = CASDataID(rawValue: Data([0x61]))
        try await storage.putValue(
            ActionCacheValue(entries: ["value": missingRoot.rawValue]),
            for: ActionCacheKey(rawValue: Data([0x62]))
        )

        let service = CachePurgeService(
            administration: storage,
            referenceReader: storage,
            retentionStore: storage,
            actionCacheStore: storage,
            actionCacheRootExtractor: Self.testRootExtractor
        )
        let plan = try await service.plan(
            CachePurgeRequest(
                scope: .cas,
                now: Date().addingTimeInterval(60),
                gracePeriod: .seconds(30)
            )
        )

        #expect(plan.candidates.map(\.identifier) == [orphan.rawValue])
        #expect(plan.danglingRootCount == 1)
    }

    @Test
    func casPlanTraversalBoundsConcurrencyAndMatchesTheSerialResult() async throws {
        let storage = InMemoryStorage()
        var expectedReachable: Set<Data> = []
        for index in 0 ..< 80 {
            let leaf = try await storage.save(ByteStreamSupport.make(Data([UInt8(index % 256)])))
            let root = try await storage.put(
                CASObject(bytes: ByteStreamSupport.make(Data([0xA0])), references: [leaf])
            )
            expectedReachable.insert(leaf.rawValue)
            expectedReachable.insert(root.rawValue)
            try await storage.putValue(
                ActionCacheValue(entries: ["value": root.rawValue]),
                for: ActionCacheKey(rawValue: Data([UInt8(index % 256), 0xFF]))
            )
        }
        let spy = ConcurrencyTrackingReferenceReader(wrapping: storage)

        let service = CachePurgeService(
            administration: storage,
            referenceReader: spy,
            retentionStore: storage,
            actionCacheStore: storage,
            actionCacheRootExtractor: Self.testRootExtractor
        )
        let plan = try await service.plan(
            CachePurgeRequest(
                scope: .cas,
                now: Date().addingTimeInterval(60),
                gracePeriod: .seconds(30)
            )
        )

        #expect(plan.candidates.isEmpty)
        let peak = await spy.peakConcurrentCalls
        #expect(peak <= 32)
        #expect(peak > 1)
    }

    @Test
    func casPlanRejectsAnUnrecognizedActionCacheValue() async throws {
        let storage = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x70]))
        try await storage.putValue(
            ActionCacheValue(entries: ["unexpected": Data([0x01])]),
            for: key
        )
        let service = CachePurgeService(
            administration: storage,
            referenceReader: storage,
            retentionStore: storage,
            actionCacheStore: storage,
            actionCacheRootExtractor: Self.testRootExtractor
        )

        await #expect(throws: CachePurgeError.unrecognizedActionCacheValue(key)) {
            try await service.plan(
                CachePurgeRequest(scope: .cas, gracePeriod: .seconds(30))
            )
        }
    }

    @Test
    func executeCallsBatchDeleteOnceWithAllVerifiedCandidates() async throws {
        let storage = InMemoryStorage()
        let keys = try await (0 ..< 3).asyncMap { index in
            let key = ActionCacheKey(rawValue: Data([UInt8(index)]))
            try await storage.putValue(ActionCacheValue(entries: ["value": Data([0x01])]), for: key)
            return key
        }
        let spy = BatchCountingAdministration(wrapping: storage)
        let service = CachePurgeService(administration: spy)
        let plan = try await service.plan(
            CachePurgeRequest(
                scope: .actionCache,
                now: Date().addingTimeInterval(60),
                olderThan: .seconds(30)
            )
        )

        let result = try await service.execute(plan, confirm: true)

        #expect(result.deletedCount == 3)
        #expect(result.failedCount == 0)
        #expect(await spy.batchCallCount == 1)
        for key in keys {
            #expect(try await storage.getValue(for: key) == nil)
        }
    }

    @Test
    func executeReportsProviderFailuresWithoutAborting() async throws {
        let storage = InMemoryStorage()
        let key = ActionCacheKey(rawValue: Data([0x50]))
        try await storage.putValue(ActionCacheValue(entries: ["value": Data([0x01])]), for: key)
        let objects = try await storage.listObjects(of: .actionCache)
        let failing = FailingBatchAdministration(objects: objects)
        let service = CachePurgeService(administration: failing)
        let plan = try await service.plan(
            CachePurgeRequest(
                scope: .actionCache,
                now: Date().addingTimeInterval(60),
                olderThan: .seconds(30)
            )
        )

        let result = try await service.execute(plan, confirm: true)

        #expect(result.deletedCount == 0)
        #expect(result.failedCount == 1)
    }

    @Test
    func executeRequiresConfirmation() async throws {
        let service = CachePurgeService(administration: InMemoryStorage())
        let plan = CachePurgePlan(scope: .staging, candidates: [], skippedCount: 0)

        await #expect(throws: CachePurgeError.confirmationRequired) {
            try await service.execute(plan, confirm: false)
        }
    }

    @Test
    func inMemoryBatchDeleteAppliesTheSameRevisionRuleToEachObject() async throws {
        let storage = InMemoryStorage()
        let staleID = try await storage.save(ByteStreamSupport.make(Data([0x40])))
        let freshID = try await storage.save(ByteStreamSupport.make(Data([0x41])))
        let objects = try await storage.listObjects(of: .cas).sorted { $0.key < $1.key }
        let stale = try #require(objects.first { $0.identifier == staleID.rawValue })
        let fresh = try #require(objects.first { $0.identifier == freshID.rawValue })

        // Overwriting stale's metadata by deleting and re-saving under the same
        // content would change its ID, so simulate a stale revision directly.
        let forgedStale = CacheObject(
            key: stale.key,
            kind: .cas,
            identifier: stale.identifier,
            modifiedAt: stale.modifiedAt,
            byteCount: stale.byteCount,
            revision: StorageRevision(rawValue: Data([0xFF]))
        )

        let result = try await storage.delete([forgedStale, fresh])

        #expect(result.deletedCount == 1)
        #expect(result.skippedCount == 1)
        #expect(result.failures.isEmpty)
        #expect(try await storage.load(id: staleID) != nil)
        #expect(try await storage.load(id: freshID) == nil)
    }

    @Test
    func inMemoryDeleteRejectsMetadataFromAnotherKey() async throws {
        let storage = InMemoryStorage()
        let id = try await storage.save(ByteStreamSupport.make(Data([0x30])))
        let stored = try #require(try await storage.listObjects(of: .cas).first)
        let forged = CacheObject(
            key: "cas/not-the-stored-object",
            kind: .cas,
            identifier: id.rawValue,
            modifiedAt: stored.modifiedAt,
            byteCount: stored.byteCount,
            revision: stored.revision
        )

        #expect(try await storage.delete(forged) == .revisionChanged)
        #expect(try await storage.load(id: id) != nil)
    }
}

private struct NonAuthoritativeRetentionStore: CASRetentionStore {
    func retentionSnapshot() async throws -> CASRetentionSnapshot {
        CASRetentionSnapshot(anchors: [], isAuthoritative: false)
    }

    func putRetentionAnchor(_: CASRetentionAnchor) async throws {}

    func deleteRetentionAnchor(_: CASRetentionAnchor) async throws -> CacheDeleteResult {
        .notFound
    }
}

private actor BatchCountingAdministration: CacheAdministration {
    private let wrapped: InMemoryStorage
    private(set) var batchCallCount = 0

    init(wrapping wrapped: InMemoryStorage) {
        self.wrapped = wrapped
    }

    func listObjects(of kind: CacheObjectKind) async throws -> [CacheObject] {
        try await wrapped.listObjects(of: kind)
    }

    func delete(_ object: CacheObject) async throws -> CacheDeleteResult {
        try await wrapped.delete(object)
    }

    func delete(_ objects: [CacheObject]) async throws -> CacheBatchDeleteResult {
        batchCallCount += 1
        return try await wrapped.delete(objects)
    }
}

private struct FailingBatchAdministration: CacheAdministration {
    let objects: [CacheObject]

    func listObjects(of _: CacheObjectKind) async throws -> [CacheObject] {
        objects
    }

    func delete(_: CacheObject) async throws -> CacheDeleteResult {
        .deleted
    }

    func delete(_ objects: [CacheObject]) async throws -> CacheBatchDeleteResult {
        CacheBatchDeleteResult(
            deletedCount: 0,
            skippedCount: 0,
            failures: objects.map { CacheDeleteFailure(key: $0.key, reason: "simulated provider failure") }
        )
    }
}

/// Records overlapping `references(of:)` calls so tests can assert the
/// planner's traversal stays within its concurrency bound.
private struct ConcurrencyTrackingReferenceReader: CASReferenceReader, Sendable {
    private let wrapped: any CASReferenceReader
    private let counter = ConcurrencyCounter()

    init(wrapping wrapped: any CASReferenceReader) {
        self.wrapped = wrapped
    }

    var peakConcurrentCalls: Int {
        get async { await counter.peak }
    }

    func references(of id: CASDataID) async throws -> [CASDataID]? {
        await counter.enterAndWaitForOverlap()
        do {
            let result = try await wrapped.references(of: id)
            await counter.exit()
            return result
        } catch {
            await counter.exit()
            throw error
        }
    }
}

private actor ConcurrencyCounter {
    private var inFlight = 0
    private(set) var peak = 0
    private var overlapWaiter: CheckedContinuation<Void, Never>?

    func enterAndWaitForOverlap() async {
        inFlight += 1
        peak = Swift.max(peak, inFlight)
        guard inFlight > 1 else {
            // Keep the first read in flight until a peer arrives.
            await withCheckedContinuation { continuation in
                overlapWaiter = continuation
            }
            return
        }

        overlapWaiter?.resume()
        overlapWaiter = nil
    }

    func exit() {
        inFlight -= 1
    }
}
