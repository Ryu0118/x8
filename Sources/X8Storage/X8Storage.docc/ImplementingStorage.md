# Implementing storage

Implement X8's data contracts without depending on a particular CLI or provider SDK.

## Start with the data plane

An implementation used by X8CLI conforms to both ``CASStore`` and
``ActionCacheStore``. Keep provider SDK types inside your storage module;
the contracts accept X8 domain values and ``ByteStream``.

`get(id:)` returns a complete CAS object, including its ordered references.
`load(id:)` returns only its payload. `put(_:)` preserves the complete object;
`save(_:)` stores a payload with no references. An identifier returned by a
write must work for subsequent reads and references in the same cache domain.

Treat CAS identifiers as opaque. Do not reinterpret incoming identifiers as
provider hashes or replace them with ETags. Preserve Action Cache key bytes,
entry names, and entry bytes without reconstructing their meaning. A provider
revision used for conditional deletion is a separate concept from a CAS ID.

## Preserve misses, errors, and streams

Return `nil` only for a confirmed missing record. Authentication, transport,
throttling, and decoding failures must remain errors. Turning them into misses
would prevent a caller from making an informed failure-policy decision.

Return a lazy ``ByteStream`` for payloads and preserve cancellation and
backpressure while consuming uploads. Do not buffer whole objects by default.
If your provider requires replayable upload bodies, use bounded streaming or
temporary-file staging with explicit cleanup. Bound any metadata decoding.

The complete example under `Examples/CustomStorageCLI` intentionally buffers
bounded records in memory to demonstrate the contracts. It is non-persistent
and is not a model for production remote I/O.

## Add administration deliberately

``CacheAdministration`` lists observations and conditionally deletes their
exact revisions. ``CASReferenceReader`` traverses references without loading
entire payloads. ``CASRetentionStore`` supplies roots and leases; claim an
authoritative snapshot only when it covers the complete cache domain.

See <doc:StorageAdministration> for revision races and retention requirements.
Implementing basic read/write contracts does not imply that garbage collection
is supported or safe.

## Connect an executable

Build your own executable on X8CLI, the shared x8 command interface. Your
executable owns configuration and authentication, constructs the storage
implementation, and supplies its cleanup operation. Neither a CLI-specific
storage protocol nor changes to the official S3-only executable are required.

Test missing records, provider failures, byte/reference round trips, stream
failures, cancellation, and cleanup with deterministic clients. Put real
provider and socket tests in separate integration suites.
