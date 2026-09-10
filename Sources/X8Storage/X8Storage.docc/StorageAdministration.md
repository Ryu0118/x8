# Cache administration

Cache administration is deliberately separate from the data-plane protocols.
``CacheAdministration`` lists provider metadata and deletes objects only
when their observed ``StorageRevision`` still matches at the moment of
deletion. A changed or missing revision is reported as a skipped deletion,
so a purge cannot remove a newer replacement discovered after planning.

## Batch deletion and its race window

`CacheAdministration.delete(_ objects:)` deletes many objects in one call so
a purge of tens of thousands of objects finishes in seconds rather than
hours. `CachePurgeExecutor` re-lists the scope immediately before calling it
and only passes objects whose revision still matched that fresh listing —
but the batch request itself is not necessarily atomic per key at the
provider. AWS S3's `DeleteObjects` accepts and enforces a per-object ETag
precondition; Cloudflare R2's `DeleteObjects` is confirmed to ignore it and
delete unconditionally regardless of which revision was sent. The remaining
race window is therefore the time between that fresh listing and the batch
request landing at the provider, not the whole plan-to-confirm window: a key
rewritten inside that narrow window can still be deleted on a provider that
ignores the precondition. This is accepted as safe for an administrative
purge that already requires `--confirm`, because the outcomes are all
recoverable — an Action Cache key deleted this way costs one extra cache
miss, and a CAS key deleted this way costs one broken cache entry with no
build failure, since a missing CAS object is reported as `OBJECT_NOT_FOUND`
and Xcode compiles locally.

## Age-based cleanup

Staging and Action Cache objects can be selected by their provider
``CacheObject/modifiedAt`` timestamp. Objects without a timestamp or a
revision are retained because their age or identity cannot be proved safely.

## CAS cleanup

CAS cleanup is reachability-based. The live root set comes from two sources:
every current Action Cache value (via an injected `(ActionCacheValue) throws
-> [CASDataID]?` closure — see `X8Kit`'s `ActionCacheRootExtractor` for the
concrete decoder), plus any explicit roots and leases in
``CASRetentionStore``. ``CASReferenceReader`` traverses each immutable
object's ordered references from that combined root set. The purge refuses
to plan when the retention snapshot is not authoritative, when a referenced
object is missing, or when the graph exceeds the safety bound.

An S3 backend's retention namespace is authoritative when its documents are
valid and either an explicit X8 retention marker exists or the namespace has
no anchors at all — an empty namespace is trivially complete, since there is
nothing an incomplete listing could have missed. This means CAS purge works
on a bucket that has never had an explicit retention anchor written to it:
its root set comes entirely from the Action Cache in that case. Explicit
anchors remain available as an additional pinning mechanism and, once any
exist, still require the marker to be trusted.

### Grace period sizing

An object a build has written but not yet referenced from a `PutValue` call
is unreachable from this purge's perspective, purely because nothing points
to it yet. The `--grace-period` (or equivalent `gracePeriod` on
`CachePurgeRequest`) is what protects such an object from being selected
before its build finishes: only objects both unreachable *and* older than
the grace period become candidates. Set it longer than the slowest build
that may run against this cache, plus expected clock skew between the
machine planning the purge and the one that wrote the object — not just
"long enough that it feels safe."

### Dangling Action Cache roots

A CAS purge (or an operator error, or a partially completed migration) can
leave an Action Cache entry whose extracted root is absent. That root
contributes nothing to reachability and is reported through
`CachePurgePlan.danglingRootCount` rather than treated as an error: a
dangling entry has nothing left to protect, so tolerating it is what lets
CAS purge run at all on a bucket in that state, rather than requiring the
Action Cache to be purged first. A *missing* object reached by traversing an
otherwise-present reference (rather than a dangling root itself) still fails
the plan closed, because that indicates a graph the purge cannot reason
about safely.

Purge always plans first. A caller must separately confirm the
plan before execution, and the execution phase rechecks each provider
revision.
