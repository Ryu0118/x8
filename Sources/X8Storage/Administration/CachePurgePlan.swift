import Foundation

/// A dry-run selection of objects that may be deleted safely.
///
/// A plan is an observation, not a lease on the selected objects. Execution
/// must re-list the namespace and recheck each candidate's `StorageRevision`
/// immediately before deletion. Objects without sufficient metadata are
/// counted as skipped rather than guessed safe.
public struct CachePurgePlan: Sendable {
    /// The requested scope.
    public let scope: CachePurgeScope

    /// Objects selected by the age and reachability rules.
    public let candidates: [CacheObject]

    /// Objects skipped because their metadata was incomplete or they were reachable.
    public let skippedCount: Int

    /// Action Cache entries whose root CAS object is already missing.
    ///
    /// These entries have nothing left to protect, so CAS planning tolerates
    /// them rather than failing closed; this count lets an operator see how
    /// many Action Cache entries are already dangling.
    public let danglingRootCount: Int

    /// Creates a purge plan.
    public init(
        scope: CachePurgeScope,
        candidates: [CacheObject],
        skippedCount: Int,
        danglingRootCount: Int = 0
    ) {
        self.scope = scope
        self.candidates = candidates
        self.skippedCount = skippedCount
        self.danglingRootCount = danglingRootCount
    }

    /// The total bytes known for selected objects.
    public var candidateBytes: Int64 {
        candidates.reduce(into: Int64.zero) { total, object in
            guard let byteCount = object.byteCount else { return }
            let (sum, overflow) = total.addingReportingOverflow(byteCount)
            total = overflow ? .max : sum
        }
    }
}

/// The outcome counts from one confirmed purge.
///
/// `skippedCount` includes objects that disappeared or changed between planning
/// and conditional deletion; those races are safe outcomes, not failures.
/// `failedCount` covers objects a provider reported as failed rather than
/// absent or changed.
public struct CachePurgeResult: Sendable {
    /// The number of objects deleted.
    public let deletedCount: Int

    /// The number of objects that were absent or changed and therefore retained.
    public let skippedCount: Int

    /// The number of objects a provider reported as failed to delete.
    public let failedCount: Int

    /// Creates a purge result.
    public init(deletedCount: Int, skippedCount: Int, failedCount: Int = 0) {
        self.deletedCount = deletedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
    }
}
