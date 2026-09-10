import Foundation

/// Selects the cache namespace and cleanup rule for an administrative purge.
public enum CachePurgeScope: String, CaseIterable, Sendable {
    /// Incomplete or quarantined uploads.
    case staging

    /// Mutable action-to-result records.
    case actionCache

    /// Immutable objects selected by reachability-based garbage collection.
    case cas
}

/// Describes one requested purge operation.
///
/// `now` makes planning deterministic, `olderThan` selects stale staging or
/// Action Cache objects, and `gracePeriod` protects newly unreachable CAS
/// objects. The request is only input to planning; it does not authorize
/// deletion.
public struct CachePurgeRequest: Sendable {
    /// The namespace to inspect.
    public let scope: CachePurgeScope

    /// The current time used to calculate the age cutoff.
    public let now: Date

    /// The age threshold for staging or Action Cache objects.
    public let olderThan: Duration

    /// The grace period for unreachable CAS objects.
    public let gracePeriod: Duration?

    /// Creates a purge request.
    public init(
        scope: CachePurgeScope,
        now: Date = Date(),
        olderThan: Duration = .zero,
        gracePeriod: Duration? = nil
    ) {
        self.scope = scope
        self.now = now
        self.olderThan = olderThan
        self.gracePeriod = gracePeriod
    }
}

extension CachePurgeScope {
    var objectKind: CacheObjectKind {
        switch self {
        case .staging: .staging
        case .actionCache: .actionCache
        case .cas: .cas
        }
    }
}
