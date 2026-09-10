import X8Storage

/// The result of planning and optionally executing one cache purge.
///
/// `plan` is always present so a frontend can display or audit the selected
/// objects. `result` is `nil` for dry runs and unconfirmed requests; it is
/// populated only after the provider-neutral executor has revalidated the
/// plan and attempted conditional deletions.
public struct CachePurgeOutcome: Sendable {
    /// The dry-run selection made before any deletion.
    public let plan: CachePurgePlan

    /// The deletion counts, or `nil` when the operation remained a plan.
    public let result: CachePurgeResult?

    /// Creates a purge outcome.
    public init(plan: CachePurgePlan, result: CachePurgeResult?) {
        self.plan = plan
        self.result = result
    }
}

/// Runs cache administration through provider-neutral storage capabilities.
///
/// The runner is the reusable Kit use-case boundary for purge commands. It
/// owns neither argument parsing nor backend construction: a frontend supplies
/// the storage capabilities, chooses presentation, and decides whether to
/// confirm the generated plan.
public struct CachePurgeRunner: Sendable {
    private let service: CachePurgeService

    /// Creates a purge runner for one storage domain.
    ///
    /// CAS purge requests additionally require `referenceReader`,
    /// `retentionStore`, and `actionCacheStore` (to derive the scope's live
    /// root set from current Action Cache values); age-based staging and
    /// Action Cache requests need only `administration`.
    public init(
        administration: any CacheAdministration,
        referenceReader: (any CASReferenceReader)? = nil,
        retentionStore: (any CASRetentionStore)? = nil,
        actionCacheStore: (any ActionCacheStore)? = nil
    ) {
        let extractor = ActionCacheRootExtractor()
        service = CachePurgeService(
            administration: administration,
            referenceReader: referenceReader,
            retentionStore: retentionStore,
            actionCacheStore: actionCacheStore,
            actionCacheRootExtractor: extractor.roots(in:)
        )
    }

    /// Plans a purge and deletes only after explicit confirmation.
    ///
    /// A dry run or an unconfirmed request returns the plan without deletion.
    /// When both gates allow execution, the result still reports races as
    /// skipped objects rather than deleting a changed replacement.
    ///
    /// - Parameters:
    ///   - request: The scope, reference time, and safety windows to plan.
    ///   - dryRun: Whether execution must be skipped after planning.
    ///   - confirm: The explicit destructive-action confirmation.
    /// - Returns: The plan and, when executed, its deletion counts.
    /// - Throws: If the required capabilities or safety evidence are missing.
    public func run(
        request: CachePurgeRequest,
        dryRun: Bool,
        confirm: Bool
    ) async throws -> CachePurgeOutcome {
        let plan = try await service.plan(request)
        guard !dryRun, confirm else {
            return CachePurgeOutcome(plan: plan, result: nil)
        }
        let result = try await service.execute(plan, confirm: true)
        return CachePurgeOutcome(plan: plan, result: result)
    }
}
