# ``X8Kit``

Reusable application-layer building blocks for Xcode compilation-cache tools.

## Overview

X8Kit contains the cache use cases behind the `x8` commands, one type per use
case: `XcodeCacheSession` owns one invocation-scoped cache proxy and exposes
the Xcode cache environment without running `xcodebuild`, `XcodeServeRunner`
owns a long-lived Unix-domain-socket proxy for clients that configure the
endpoint themselves, `X8Doctor` checks configuration, storage, and the local
proxy, and `CachePurgeRunner` plans and executes cache maintenance. All of
them receive storage boundaries instead of knowing how cache records are
persisted.

A CAS purge derives its live root set from the current Action Cache: the
runner constructs `ActionCacheRootExtractor` and passes its `roots(in:)` as
the closure `CachePurgePlanner` (in `X8Storage`) uses to read Xcode's
`CompilationCacheService_Cas_V1_CASObject` reference lists at plan time.
`X8Storage` never imports the generated protobuf type; only `X8Kit`, which
owns it, does.

X8Kit is an internal implementation layer of `X8CLI`, not a directly
embeddable public library: it carries no `public` API of its own, and a
custom executable is expected to build on `X8CLI` instead. See the
[custom CLI guide](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli)
for configuration ownership, storage injection, and a complete example.

X8Kit does not select or construct a storage backend, and it carries no
YAML-configuration or object-storage-shaped types. `X8CLI` supplies the
`X8Storage.CASStore` and `X8Storage.ActionCacheStore` implementations it
runs against, so X8Kit works with any backend without enabling the optional
S3 trait or adopting the `X8Config` package's configuration model.

Filesystem side effects are injected through `FileManagerProtocol`. The
runner and server initializers default to the live `FileManager`, while
tests can provide a deterministic implementation. `X8Config`'s
`X8ConfigurationLoader` and `X8ConfigurationResolver` provide YAML-based
configuration loading and resolution for the official `x8` executable;
X8Kit itself only receives already-constructed storage boundaries and
profile identifiers.

## Topics

- <doc:XcodeCompilationCaching>
- <doc:XcodeCacheRuntime>
- [Prefix mapping and cache portability](https://ryu0118.github.io/x8/documentation/x8cli/prefixmapping)
