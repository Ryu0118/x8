# Storage lifetime and capabilities

Keep clients alive until all cache operations finish, and advertise capabilities through storage contracts.

## Separate construction from ownership

The configuration loader returns local construction input. `storage:` then
opens a client only for a command that needs cache access. The returned object
must conform to `CASStore` and `ActionCacheStore`; these can share one client
without exposing it to X8Kit.

When a factory fails before returning, it must release any partially created
resources itself. After a successful return, the shared CLI owns the command's
use of that object and invokes `shutdown:` exactly once. Omit the closure only
when the object does not need asynchronous cleanup or its resources belong to
an external owner.

For example, a client-owning implementation can be connected with:

```swift
let cli = X8CLI(
    configuration: loadConfiguration,
    storage: { MyStorage(configuration: $0) },
    shutdown: { try await $0.shutdown() }
)
await cli.main()
```

The caller supplies the loader and storage type in this illustration. See
<doc:CreatingACustomCLI> for the complete buildable example.

## Finish work before closing the client

For an invocation-scoped build, the child process completes and the Kit session
shuts down before storage is closed. A standalone server drains through the Kit
handle before its client is closed. The command cannot return while its storage
operations are still using that client.

An operation error or task cancellation triggers cleanup and is then propagated.
A cleanup error does not replace an already-failing operation. If the operation
succeeded, a cleanup failure is reported without attempting shutdown again.
Factories and operations must cooperate with cancellation; cleanup must still
release resources when called from a cancelled task. A forced process kill
cannot run asynchronous cleanup.

## Optional administration

The command tree is the same for every storage implementation. Additional
capabilities are discovered through existing X8Storage conformances:

| Operation | Required capabilities |
| --- | --- |
| Xcode cache reads and writes | `CASStore`, `ActionCacheStore` |
| Age-based staging or Action Cache purge | Also `CacheAdministration` |
| Reachability-based CAS purge | Also `CASReferenceReader`, `CASRetentionStore`, `ActionCacheStore` |

Missing capabilities produce a diagnostic and a nonzero exit status. Commands
are not silently removed. CAS purge also requires an authoritative retention
snapshot; a conformance alone does not prove that deleting objects is safe —
see X8Storage's `StorageAdministration` article for the authoritative-snapshot
rule, Action Cache root derivation, first-run guidance, and the remaining
batch-deletion race window.
