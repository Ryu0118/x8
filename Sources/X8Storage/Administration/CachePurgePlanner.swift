import AsyncOperations
import Foundation
import X8Core

/// Selects purge candidates without performing deletions.
///
/// Age-based scopes require a revision and modification time. CAS planning
/// additionally requires an authoritative retention snapshot and traverses all
/// roots before selecting old unreachable objects, failing closed when the
/// graph cannot be proven safe.
struct CachePurgePlanner: Sendable {
    private static let maximumGraphObjects = 1_000_000
    private static let maximumConcurrentReads = 32

    private let administration: any CacheAdministration
    private let referenceReader: (any CASReferenceReader)?
    private let retentionStore: (any CASRetentionStore)?
    private let actionCacheStore: (any ActionCacheStore)?
    private let actionCacheRootExtractor: (@Sendable (ActionCacheValue) throws -> [CASDataID]?)?

    init(
        administration: any CacheAdministration,
        referenceReader: (any CASReferenceReader)?,
        retentionStore: (any CASRetentionStore)?,
        actionCacheStore: (any ActionCacheStore)? = nil,
        actionCacheRootExtractor: (@Sendable (ActionCacheValue) throws -> [CASDataID]?)? = nil
    ) {
        self.administration = administration
        self.referenceReader = referenceReader
        self.retentionStore = retentionStore
        self.actionCacheStore = actionCacheStore
        self.actionCacheRootExtractor = actionCacheRootExtractor
    }

    func plan(_ request: CachePurgeRequest) async throws -> CachePurgePlan {
        try validate(request)
        return try await plan(for: request)
    }

    private func validate(_ request: CachePurgeRequest) throws {
        guard request.olderThan >= .zero else {
            throw CachePurgeError.negativeDuration
        }
        guard request.gracePeriod.map({ $0 >= .zero }) ?? true else {
            throw CachePurgeError.negativeDuration
        }
    }

    private func plan(for request: CachePurgeRequest) async throws -> CachePurgePlan {
        switch request.scope {
        case .staging, .actionCache:
            try await planAgeBased(request)
        case .cas:
            try await planCAS(request)
        }
    }

    private func planAgeBased(_ request: CachePurgeRequest) async throws -> CachePurgePlan {
        let cutoff = request.now.addingTimeInterval(-request.olderThan.timeInterval)
        let objects = try await administration.listObjects(of: request.scope.objectKind)
        let candidates = objects.filter { isOlder($0, than: cutoff) }
        return CachePurgePlan(
            scope: request.scope,
            candidates: candidates,
            skippedCount: objects.count - candidates.count
        )
    }

    private func planCAS(_ request: CachePurgeRequest) async throws -> CachePurgePlan {
        guard let gracePeriod = request.gracePeriod else {
            throw CachePurgeError.missingGracePeriod
        }
        guard let retentionStore else {
            throw CachePurgeError.retentionStoreUnavailable
        }
        guard let referenceReader else {
            throw CachePurgeError.referenceReaderUnavailable
        }
        guard let actionCacheStore, let actionCacheRootExtractor else {
            throw CachePurgeError.actionCacheStoreUnavailable
        }

        let snapshot = try await retentionStore.retentionSnapshot()
        guard snapshot.isAuthoritative else {
            throw CachePurgeError.nonAuthoritativeRetention
        }
        let activeAnchors = snapshot.anchors.filter { isActive($0, at: request.now) }

        let (liveRoots, danglingRootCount) = try await liveActionCacheRoots(
            using: actionCacheStore,
            extractor: actionCacheRootExtractor,
            referenceReader: referenceReader
        )
        let anchorRoots = activeAnchors.flatMap(\.objectIDs)

        // Traverse before listing candidates so every live root is validated first.
        let reachable = try await reachableObjects(
            from: liveRoots + anchorRoots,
            using: referenceReader
        )
        let cutoff = request.now.addingTimeInterval(-gracePeriod.timeInterval)
        let objects = try await administration.listObjects(of: .cas)
        let candidates = objects.filter {
            isUnreachableAndOlder($0, than: cutoff, reachable: reachable)
        }
        return CachePurgePlan(
            scope: .cas,
            candidates: candidates,
            skippedCount: objects.count - candidates.count,
            danglingRootCount: danglingRootCount
        )
    }

    /// Reads every current Action Cache value and extracts its CAS roots.
    ///
    /// A root whose CAS object is already absent is counted as dangling
    /// rather than treated as reachable, since a dangling entry has nothing
    /// left to protect. An unparseable value fails the whole plan closed:
    /// see `CachePurgeError.unrecognizedActionCacheValue`. Reads are bounded
    /// to `maximumConcurrentReads` in flight at once so a bucket with tens or
    /// hundreds of thousands of Action Cache entries does not require one
    /// round trip per entry, sequentially.
    private func liveActionCacheRoots(
        using actionCacheStore: any ActionCacheStore,
        extractor: @escaping @Sendable (ActionCacheValue) throws -> [CASDataID]?,
        referenceReader: any CASReferenceReader
    ) async throws -> (roots: [CASDataID], danglingCount: Int) {
        let entries = try await administration.listObjects(of: .actionCache)
        var roots: [CASDataID] = []
        var danglingCount = 0

        let results = try await entries.asyncMap(
            numberOfConcurrentTasks: UInt(Self.maximumConcurrentReads)
        ) { entry in
            try await rootsForOneActionCacheEntry(
                entry,
                using: actionCacheStore,
                extractor: extractor,
                referenceReader: referenceReader
            )
        }
        for result in results {
            roots += result.roots
            danglingCount += result.dangling
        }
        return (roots, danglingCount)
    }

    private func rootsForOneActionCacheEntry(
        _ entry: CacheObject,
        using actionCacheStore: any ActionCacheStore,
        extractor: @Sendable (ActionCacheValue) throws -> [CASDataID]?,
        referenceReader: any CASReferenceReader
    ) async throws -> (roots: [CASDataID], dangling: Int) {
        let key = ActionCacheKey(rawValue: entry.identifier)
        guard let value = try await actionCacheStore.getValue(for: key) else {
            return ([], 0)
        }
        guard let extractedRoots = try extractor(value), !extractedRoots.isEmpty else {
            throw CachePurgeError.unrecognizedActionCacheValue(key)
        }
        return try await partitionByReachability(extractedRoots, using: referenceReader)
    }

    private func partitionByReachability(
        _ candidateRoots: [CASDataID],
        using referenceReader: any CASReferenceReader
    ) async throws -> (roots: [CASDataID], dangling: Int) {
        let checks = try await candidateRoots.asyncMap(
            numberOfConcurrentTasks: UInt(Self.maximumConcurrentReads)
        ) { root in
            try await (root, referenceReader.references(of: root) != nil)
        }
        let live = checks.filter(\.1).map(\.0)
        return (live, checks.count - live.count)
    }

    /// Traverses the reference graph breadth-first, one level at a time.
    ///
    /// Each level's pending IDs are fetched concurrently (bounded to
    /// `maximumConcurrentReads`), which keeps the existing shortest-depth
    /// bookkeeping and graph/depth limits intact while avoiding one
    /// sequential round trip per object.
    private func reachableObjects(
        from roots: [CASDataID],
        using reader: any CASReferenceReader
    ) async throws -> Set<CASDataID> {
        var depthByID = Dictionary(
            roots.map { ($0, 0) },
            uniquingKeysWith: { Swift.min($0, $1) }
        )
        var reachable = Set<CASDataID>()
        var currentLevel = Array(depthByID.keys)

        while !currentLevel.isEmpty {
            try validateLevel(currentLevel, depthByID: depthByID, reachable: &reachable)

            let levelReferences = try await referencesForLevel(currentLevel, using: reader)
            let nextLevel = nextLevelDepths(
                from: currentLevel,
                depthByID: depthByID,
                levelReferences: levelReferences,
                reachable: reachable
            )
            depthByID.merge(nextLevel, uniquingKeysWith: Swift.min)
            currentLevel = Array(nextLevel.keys)
        }
        return reachable
    }

    /// Marks one BFS level's IDs reachable and enforces the graph size/depth bounds.
    private func validateLevel(
        _ level: [CASDataID],
        depthByID: [CASDataID: Int],
        reachable: inout Set<CASDataID>
    ) throws {
        for id in level {
            reachable.insert(id)
            try validateGraphSize(reachable.count)
            try validateGraphDepth(depthByID[id] ?? 0)
        }
    }

    private func referencesForLevel(
        _ level: [CASDataID],
        using reader: any CASReferenceReader
    ) async throws -> [CASDataID: [CASDataID]] {
        let pairs = try await level.asyncMap(
            numberOfConcurrentTasks: UInt(Self.maximumConcurrentReads)
        ) { id in
            try await (id, references(for: id, from: reader))
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    private func nextLevelDepths(
        from level: [CASDataID],
        depthByID: [CASDataID: Int],
        levelReferences: [CASDataID: [CASDataID]],
        reachable: Set<CASDataID>
    ) -> [CASDataID: Int] {
        var nextLevel: [CASDataID: Int] = [:]
        for id in level {
            let nextDepth = (depthByID[id] ?? 0) + 1
            mergeUnreachableReferences(
                levelReferences[id] ?? [],
                depth: nextDepth,
                reachable: reachable,
                into: &nextLevel
            )
        }
        return nextLevel
    }

    /// Records each unreachable reference's shallowest observed depth so far.
    private func mergeUnreachableReferences(
        _ references: [CASDataID],
        depth: Int,
        reachable: Set<CASDataID>,
        into nextLevel: inout [CASDataID: Int]
    ) {
        for reference in references where !reachable.contains(reference) {
            nextLevel[reference] = Swift.min(nextLevel[reference] ?? depth, depth)
        }
    }

    private func references(
        for id: CASDataID,
        from reader: any CASReferenceReader
    ) async throws -> [CASDataID] {
        guard let references = try await reader.references(of: id) else {
            throw CachePurgeError.missingReferencedObject(id)
        }
        return references
    }

    private func validateGraphSize(_ count: Int) throws {
        guard count <= Self.maximumGraphObjects else {
            throw CachePurgeError.graphLimitExceeded
        }
    }

    private func validateGraphDepth(_ depth: Int) throws {
        guard depth < Self.maximumGraphObjects else {
            throw CachePurgeError.graphLimitExceeded
        }
    }

    private func isOlder(_ object: CacheObject, than cutoff: Date) -> Bool {
        guard object.revision != nil, let modifiedAt = object.modifiedAt else { return false }
        return modifiedAt < cutoff
    }

    private func isActive(_ anchor: CASRetentionAnchor, at date: Date) -> Bool {
        anchor.expiresAt.map { $0 > date } ?? true
    }

    private func isUnreachableAndOlder(
        _ object: CacheObject,
        than cutoff: Date,
        reachable: Set<CASDataID>
    ) -> Bool {
        guard isOlder(object, than: cutoff) else { return false }
        return !reachable.contains(CASDataID(rawValue: object.identifier))
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
