# Cache administration from X8Kit

``CachePurgeRunner`` is the reusable application-layer entry point for cache
maintenance. It accepts the provider-neutral capabilities from `X8Storage`
and does not construct an S3 client or interpret an Action Cache value.

The runner produces a ``CachePurgeOutcome`` containing the selected objects.
It executes only when the caller supplies confirmation and does not request a
dry run. A custom CLI can therefore reuse the same safety policy while owning
its own argument parsing, output format, and backend composition.

## CAS purge derives its roots from the Action Cache

A CAS scope requires an `actionCacheStore` in addition to the retention and
reference-reading capabilities `X8Storage` already defines. The runner
constructs `ActionCacheRootExtractor` and passes its `roots(in:)` as the
closure `CachePurgePlanner` (in `X8Storage`) uses to derive the current live
root set: Xcode stores a `CompilationCacheService_Cas_V1_CASObject` under
each entry's `value` key, and that object's `references` are the roots.
`X8Storage` never imports the generated protobuf type; only `X8Kit`, which
owns it, does.

CAS purge therefore needs no explicit retention anchor: its live root set is
the current Action Cache, read fresh at plan time. An explicit
`CASRetentionAnchor` is available for pinning specific objects regardless of
Action Cache churn (a release build's outputs, say); it is additive, not
required.

An Action Cache value whose extractor cannot find any CAS-object-shaped
entry fails the whole plan closed — that is a code or protocol mismatch to
fix, not a case where deleting still-live objects should be risked. An
Action Cache entry whose root CAS object is already missing (a dangling
entry) is reported via `CachePurgePlan.danglingRootCount` rather than
failing the plan, since a dangling entry protects nothing.
