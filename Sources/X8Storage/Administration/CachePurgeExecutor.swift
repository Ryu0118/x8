/// Executes a previously planned purge with revision-aware deletion checks.
///
/// The executor is intentionally separate from planning so a caller can review
/// or confirm a plan before any destructive operation. It re-lists the target
/// namespace and skips candidates that are missing or have changed revisions.
struct CachePurgeExecutor: Sendable {
    private let administration: any CacheAdministration

    init(administration: any CacheAdministration) {
        self.administration = administration
    }

    func execute(
        _ plan: CachePurgePlan,
        confirm: Bool
    ) async throws -> CachePurgeResult {
        guard confirm else {
            throw CachePurgeError.confirmationRequired
        }

        // Re-list immediately before deletion so a stale or removed candidate is skipped, not deleted.
        let currentObjects = try await administration.listObjects(of: plan.scope.objectKind)
        let currentByKey = Dictionary(
            currentObjects.map { ($0.key, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let (verified, staleCount) = verify(plan.candidates, against: currentByKey)
        let batch = try await administration.delete(verified)

        return CachePurgeResult(
            deletedCount: batch.deletedCount,
            skippedCount: staleCount + batch.skippedCount,
            failedCount: batch.failures.count
        )
    }

    private func verify(
        _ candidates: [CacheObject],
        against currentByKey: [String: CacheObject]
    ) -> (verified: [CacheObject], staleCount: Int) {
        let verified = candidates.compactMap { candidate in
            current(for: candidate, in: currentByKey)
        }
        return (verified, candidates.count - verified.count)
    }

    /// Returns the current object for `candidate` only when it still has the
    /// same revision the plan observed, so a stale or changed object is
    /// treated as a skip rather than a delete.
    private func current(
        for candidate: CacheObject,
        in currentByKey: [String: CacheObject]
    ) -> CacheObject? {
        guard let revision = candidate.revision,
              let current = currentByKey[candidate.key],
              current.revision == revision
        else { return nil }
        return current
    }
}
