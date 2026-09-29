# Xcode compilation caching

How Xcode's remote compilation cache works on the wire, and where X8 sits in
that path.

## Overview

Xcode 26 introduced opt-in compilation caching. Apple's release notes describe
it as caching "the results of compilations that were produced for a set of
source file inputs" and replaying "the prior compilation results directly from
the cache" when the same inputs are compiled again, with the largest gains on
branch switches and clean builds. The feature is built on LLVM's
content-addressable storage (CAS) and its action cache; the local cache lives
in DerivedData.

A remote cache extends that local cache across machines: a CI fleet populates
it, developer machines and other agents read from it. Xcode does not talk to
object storage itself. It talks gRPC over a Unix-domain socket to a *remote
cache service*, and X8 is such a service: it implements the two gRPC services
Xcode expects and stores their records in an S3-compatible bucket.

The three build settings that wire this up are:

| Build setting | Effect |
| --- | --- |
| `COMPILATION_CACHE_ENABLE_CACHING=YES` | Turns on compilation caching. Apple's "Enable Compilation Caching" build setting. |
| `COMPILATION_CACHE_ENABLE_PLUGIN=YES` | Loads the toolchain's CAS plugin so cache lookups and stores go through the plugin instead of the local on-disk CAS only. |
| `COMPILATION_CACHE_REMOTE_SERVICE_PATH=<socket>` | The Unix-domain socket the plugin connects to. This is a filesystem path, not a host and port. |

X8's cache-settings contract emits these three values plus six
prefix-mapping settings: four enable flags and two mapping-value settings
and an empty `CLANG_MODULES_BUILD_SESSION_FILE`, described in
the [prefix-mapping guide](https://ryu0118.github.io/x8/documentation/x8cli/prefixmapping).
Xcode's build system resolves them as
build settings rather than inherited environment, so `x8 xcodebuild` appends
them as `SETTING=VALUE` command-line overrides; the standalone
`x8 serve --print-cache-settings` output is the same contract for a client
that configures itself.

## Two services, two kinds of record

The wire contract is two proto3 services checked in under
`Protos/compilation_cache_service/`. They map directly onto LLVM's two CAS
concepts:

- `CASDBService` is LLVM's `ObjectStore`: immutable, content-addressed
  objects. An object is a blob plus an ordered list of references to other
  objects, so objects form a DAG (per LLVM's CAS documentation).
- `KeyValueDB` is LLVM's `ActionCache`: a key-value store that maps "an input
  CASObject to an output CASObject with their CASIDs". The key identifies a
  compilation action; the value points at its cached outputs.

```mermaid
flowchart LR
accTitle: Cache Record Shapes
accDescr: Action Cache maps an opaque key to small value entries; CAS maps an opaque CASDataID to a CASObject (blob plus references) or CASBlob (blob only), and Action Cache value entries carry CAS IDs into the CAS side.
    subgraph AC["Action Cache — KeyValueDB"]
        direction TB
        ACK["key: bytes<br/>(opaque action digest)"]
        ACV["Value entries: map string to bytes<br/>small result record"]
        ACK -- "GetValue / PutValue" --> ACV
        ACO["GetValue outcome:<br/>SUCCESS / KEY_NOT_FOUND / ERROR"]
    end

    subgraph CAS["CAS — CASDBService"]
        direction TB
        ID["CASDataID id: bytes<br/>(opaque)"]
        OBJ["CASObject<br/>blob + repeated references"]
        BLOB["CASBlob<br/>blob only, no references"]
        ID -- "Get / Put" --> OBJ
        ID -- "Load / Save" --> BLOB
        CO["Get/Load outcome:<br/>SUCCESS / OBJECT_NOT_FOUND / ERROR"]
    end

    ACV -. "entries carry CAS IDs" .-> ID
```

The two services are deliberately different shapes:

| | Action Cache (`KeyValueDB`) | CAS (`CASDBService`) |
| --- | --- | --- |
| Address | Opaque action key, chosen by the compiler | Opaque `CASDataID`, chosen by the CAS |
| Payload | Small map of string to bytes | Arbitrary bytes, optionally with references |
| Mutability | Replaceable per key (`PutValue` overwrites) | Immutable; same content, same ID |
| Miss | `KEY_NOT_FOUND` | `OBJECT_NOT_FOUND` |
| Failure | `ERROR` with `ResponseError.description` | `ERROR` with `ResponseError.description` |
| X8 boundary | `X8Storage.ActionCacheStore` | `X8Storage.CASStore` |

`Put`/`Get` carry a full `CASObject` (blob plus references). `Save`/`Load`
carry a bare `CASBlob` with no references; this is the raw-bytes path. Both
read RPCs accept `write_to_disk`, which asks the service to return a
`file_path` instead of inline `data` so large outputs never round-trip
through a gRPC message body. `CASBytes` is a `oneof` of `data` or
`file_path` in both directions, so a client can also hand the service a file
on `Put`/`Save`.

The miss-versus-error split is on the wire, not an X8 invention. A
`KEY_NOT_FOUND` or `OBJECT_NOT_FOUND` means "compile it"; an `ERROR` means the
service could not answer. X8 preserves that distinction end to end so a
storage outage degrades to a slower build rather than a failed one.

## CAS identifiers are opaque

`CASDataID.id` is bytes. LLVM's documentation states that an ID "created by
different ObjectStore[s] cannot be cross-referenced or compared", and the
plugin API hands the compiler whatever digest the plugin returns. X8 therefore
treats the ID as an opaque token: it is never re-hashed, never replaced by an
S3 ETag or key, and is mapped to a provider location only at the
storage-adapter boundary (`X8S3` uses a hex encoding of the same bytes under a
`cas/` prefix). The same holds for `KeyValueDB` keys.

## The object graph

A compiled output is not one blob. The compiler stores its result as a small
tree of CAS objects, and the action-cache value points at the root. Apple
does not document the node layout; the diagram shows the shape the protocol
permits.

```mermaid
flowchart TB
accTitle: CAS Object Graph
accDescr: An Action Cache key resolves to a value whose entry points at a root CASObject; the root references object-code, diagnostics, dependency-record, and precompiled-module CASObjects, which in turn reference raw CASBlob leaves.
    AK["Action Cache key<br/>(digest of inputs, flags, toolchain)"]
    AV["Action Cache value<br/>entries.value points at root CAS ID"]
    ROOT["CASObject: compilation result<br/>blob: result metadata<br/>references below"]
    OBJ_O["CASObject: object code (.o)"]
    DIAG["CASObject: diagnostics"]
    DEPS["CASObject: dependency record"]
    PCM["CASObject: precompiled module<br/>(shared by many results)"]
    LEAF1["CASBlob: raw bytes"]
    LEAF2["CASBlob: raw bytes"]

    AK -- "GetValue" --> AV
    AV -- "Get(root)" --> ROOT
    ROOT --> OBJ_O
    ROOT --> DIAG
    ROOT --> DEPS
    ROOT --> PCM
    OBJ_O --> LEAF1
    PCM --> LEAF2
```

Three properties follow from content addressing:

- Identical content has one ID. A precompiled module shared by two hundred
  translation units is stored once and referenced two hundred times.
- References are by ID, so a parent can only be written after its children
  exist. A client stores leaves first; X8 does not validate that referenced
  IDs are present, mirroring the protocol.
- The action-cache value is metadata, not the compiled bytes. `X8Core`'s
  `X8Core.ActionCacheValue` preserves the entries verbatim; the `value`
  entry contains serialized result metadata that refers to CAS IDs.

## A build, end to end

The sequence below is one compilation action on a cold cache, followed by the
same action on another machine. The client is the CAS plugin loaded by the
Xcode toolchain; which process holds the socket connection is not documented
and does not affect the protocol.

```mermaid
sequenceDiagram
accTitle: Build Sequence
accDescr: A miss path (GetValue KEY_NOT_FOUND, compile, Save and Put the result, PutValue) followed by a hit path on another machine (GetValue SUCCESS, Get and Load reuse the cached CAS objects, compiler not run) and an error path (GetValue ERROR, compile locally, build continues).
    autonumber
    participant C1 as Xcode toolchain (machine A)
    participant X as X8 proxy (Unix socket)
    participant S as S3-compatible bucket
    participant C2 as Xcode toolchain (machine B)

    Note over C1,X: Miss path
    C1->>C1: compute action key K from inputs
    C1->>X: KeyValueDB.GetValue(K)
    X->>S: GET action-cache/K
    S-->>X: 404
    X-->>C1: outcome = KEY_NOT_FOUND
    C1->>C1: run compiler
    C1->>X: CASDBService.Save(blob: .o bytes)
    X->>S: PUT cas/id_o
    X-->>C1: cas_id = id_o
    C1->>X: CASDBService.Put(result metadata blob referencing id_o)
    X->>S: PUT cas/id_root
    X-->>C1: cas_id = id_root
    C1->>X: KeyValueDB.PutValue(K, value pointing at id_root)
    X->>S: PUT action-cache/K
    X-->>C1: ok

    Note over C2,X: Hit path
    C2->>C2: compute the same action key K
    C2->>X: KeyValueDB.GetValue(K)
    X->>S: GET action-cache/K
    S-->>X: value
    X-->>C2: outcome = SUCCESS, value
    C2->>X: CASDBService.Get(id_root)
    X->>S: GET cas/id_root
    X-->>C2: SUCCESS with CASObject blob and references
    C2->>X: CASDBService.Load(id_o, write_to_disk = true)
    X->>S: GET cas/id_o (streamed)
    X-->>C2: SUCCESS, file_path
    C2->>C2: materialize outputs, compiler not run

    Note over C2,S: Error path
    C2->>X: KeyValueDB.GetValue(K prime)
    X->>S: GET action-cache/K-prime
    S-->>X: 503
    X-->>C2: outcome = ERROR, description
    C2->>C2: compile locally, build continues
```

Notes on the diagram:

- The RPC names, outcomes, and `write_to_disk` behaviour are the checked-in
  protocol. The leaf-first store order follows from references being by ID.
- Step ordering within a real build is concurrent; many actions are in flight
  at once on one socket.
- The error path is what "fail open" means concretely: X8 answers `ERROR`,
  and the toolchain compiles as if no cache were configured.
- If DerivedData already holds an output, Xcode uses it and never asks the
  remote service.

## Where X8 sits

X8 is a protocol adapter. Each layer knows only the layer below it, and the
opaque identifiers pass through every layer unchanged.

```mermaid
flowchart TB
accTitle: Protocol Adapter Layers
accDescr: Xcode connects over gRPC to X8Kit's server, whose CAS and Action Cache services delegate to X8Storage's provider-neutral CASStore/ActionCacheStore boundary, which X8S3 maps onto S3 keys and a versioned envelope in the bucket.
    XC["Xcode / xcodebuild<br/>toolchain CAS plugin"]
    SOCK["Unix-domain socket<br/>COMPILATION_CACHE_REMOTE_SERVICE_PATH"]
    subgraph KIT["X8Kit — gRPC server over the socket"]
        direction LR
        CASSVC["XcodeCacheCASService<br/>CASDBService"]
        KVSVC["XcodeCacheActionCacheService<br/>KeyValueDB"]
        WIRE["XcodeCacheWire<br/>inline bytes to ByteStream<br/>file_path to response file store"]
    end
    subgraph STORAGE["X8Storage — provider-neutral boundary"]
        direction LR
        CS["CASStore<br/>get / put / load / save"]
        AS["ActionCacheStore<br/>getValue / putValue"]
    end
    subgraph S3["X8S3 — S3Storage"]
        direction LR
        KEYS["S3 key space<br/>cas/hex-id, action-cache/hex-key"]
        CODEC["S3StorageCodec<br/>versioned envelope: refs + payload"]
    end
    BUCKET[("S3-compatible bucket")]

    XC -- "gRPC" --> SOCK --> KIT
    CASSVC --> WIRE
    CASSVC --> CS
    KVSVC --> AS
    CS --> S3
    AS --> S3
    KEYS --> BUCKET
    CODEC --> BUCKET
```

Responsibilities per layer:

- **Server (X8Kit).** Owns the socket and the gRPC transport. Translates
  request bytes into a lazy `X8Storage.ByteStream` and response streams back into
  inline `data` (bounded) or a server-owned `file_path` when `write_to_disk`
  is set. Maps a `nil` from storage to `OBJECT_NOT_FOUND`/`KEY_NOT_FOUND` and
  a thrown error to `ERROR`. Records hit, miss, stored, and remote-error
  metrics. Has no idea what a bucket is.
- **Storage boundary (X8Storage).** `X8Storage.CASStore` and `X8Storage.ActionCacheStore`
  return `nil` for a miss and throw for a provider failure, so the split
  survives the layer change. Payloads cross as pull-driven `X8Storage.ByteStream`
  values; whole objects are not buffered by default. The bounded inline
  response limit and the disk-backed response file are the documented
  exceptions, and both live at this boundary.
- **Adapter (X8S3).** Maps opaque ID bytes to keys under fixed prefixes,
  wraps CAS objects in a versioned envelope that carries the reference list
  ahead of the payload, and stages CAS input locally so the body can be
  replayed to the provider. A `consumer`-role invocation wraps both stores so
  writes are rejected before any I/O and reads pass through unchanged.

## Two ways to expose the socket

Both entry points run the same server; they differ in who owns the socket and
for how long. <doc:XcodeCacheRuntime> describes the lifecycle mechanics.

```mermaid
flowchart LR
accTitle: Socket Lifecycles
accDescr: x8 xcodebuild starts a private socket for one invocation and removes it on exit; x8 serve starts a stable per-profile socket that any number of builds can reuse until it is stopped by signal or shutdown.
    subgraph A["x8 xcodebuild (invocation-scoped)"]
        direction LR
        A1["XcodeCacheSession.start"] --> A2["private socket under /private/tmp/x8/x8-cache-uuid/"]
        A2 --> A3["xcodebuild with COMPILATION_CACHE_* and *_PREFIX_MAPPING overrides"]
        A3 --> A4["xcodebuild exits: session.shutdown, socket and directory removed"]
    end
    subgraph B["x8 serve (long-lived)"]
        direction LR
        B1["XcodeServeRunner.start"] --> B2["stable socket<br/>Application Support/X8/profileID/listener.sock"]
        B2 --> B3["any number of xcodebuild / Xcode GUI builds<br/>configured with the printed settings"]
        B3 --> B4["SIGINT / SIGTERM or handle.shutdown"]
    end
```

| | `x8 xcodebuild` | `x8 serve` |
| --- | --- | --- |
| Socket | Throwaway, per invocation | Stable, per profile; existing path is refused, never unlinked |
| Settings | Injected by X8 as command-line overrides | Printed by `--print-cache-settings`; the client applies them |
| Typical client | CI job, scripted build | Xcode GUI, repeated local builds |
| Lifetime | Ends with the child process | Ends on signal, `shutdown()`, or transport failure |

The socket path is only an endpoint. Cache sharing and isolation come from
the bucket and the opaque Xcode identifiers; two proxies on different
sockets pointed at the same bucket share one cache.
