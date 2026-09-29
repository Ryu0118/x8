# ``X8Storage``

Provider-neutral storage contracts for Xcode compilation cache data.

## Overview

`X8Storage` keeps the two cache domains separate while allowing one backend
to implement both of them. ``CASStore`` handles immutable CAS blobs and
objects with ordered references. ``ActionCacheStore`` handles mutable,
opaque values addressed by an Action Cache key.

A missing item is represented by `nil`. Provider failures are thrown so a
higher layer can distinguish a cache miss from an unavailable remote service.
Byte payloads cross this boundary as ``ByteStream`` values. The Xcode protocol
adapter is responsible for translating between that stream and Xcode's
inline-bytes or file-path representation.

``ByteStream`` is pull-driven and lazy: constructing one does not consume its
source, and each iterator call requests at most one next chunk. Storage
adapters can therefore preserve provider backpressure and cancellation instead
of creating an unbounded buffering producer.

See <doc:CacheModel> for the meaning of a compilation action, its Action Cache
key and value, and the CAS records referenced by its result metadata.

See <doc:StorageAdministration> for the separate listing, revision, retention,
and purge contracts.

See <doc:ImplementingStorage> to build a storage implementation for a custom
executable using ``X8CLI``.

## Storage Flow

```text
Xcode protocol adapter <-> ByteStream <-> storage provider
                                      <-> CAS or Action Cache
```

The module does not depend on Soto, S3 request types, Unix sockets, or
protocol-specific generated code.

Filesystem checks needed by streamed file inputs are supplied through
`FileManagerProtocol`; storage adapters keep the live implementation at their
composition boundary so the file boundary can be tested independently.

## Lifetime and ownership

`ByteStream` owns only the pull operation, not a cache record. A storage
implementation owns its provider client and persistence state, while callers
own the lifetime of any returned stream and are responsible for consuming it.
Administrative capabilities are separate from the Xcode data plane: listing
produces observations, retention supplies GC roots, and purge planning and
execution decide when conditional deletion is safe.
