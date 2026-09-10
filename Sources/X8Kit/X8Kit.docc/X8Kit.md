# ``X8Kit``

Reusable application-layer building blocks for Xcode compilation-cache tools.

## Overview

X8Kit contains the cache use cases behind the `x8` commands, one type per
use case. ``XcodeCacheSession`` owns one invocation-scoped cache proxy and
exposes the Xcode cache environment without running `xcodebuild`; the outer
frontend passes that environment to its chosen Xcode client.
``XcodeServeRunner`` owns a long-lived Unix-domain-socket proxy for clients
that configure the endpoint themselves. ``X8Doctor`` checks configuration,
storage, and the local proxy, and ``CachePurgeRunner`` plans and executes
cache maintenance. All of them receive storage boundaries instead of knowing
how cache records are persisted.

Use X8CLI when you want the same command interface as the official S3-only
`x8` executable with your own storage. Use X8Kit directly when you want a
different command interface or are embedding the cache server in an existing
application. The [custom CLI guide](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli)
includes configuration ownership, storage injection, and a complete example.

``X8Kit`` does not select or construct a storage backend, and it carries no
YAML-configuration or object-storage-shaped types. A frontend supplies the
`X8Storage.CASStore` and `X8Storage.ActionCacheStore` implementations, so a custom CLI can use
X8Kit with its own backend without enabling the optional S3 trait or adopting
the `X8Config` package's configuration model.

Filesystem side effects are injected through `FileManagerProtocol`. The public
runner and server initializers default to the live `FileManager`, while tests
and custom frontends can provide a deterministic implementation. A frontend
that wants YAML-based configuration loading and resolution — `X8ConfigurationLoader`
and `X8ConfigurationResolver` — can adopt the separate `X8Config` package
target instead; X8Kit itself only receives already-constructed storage
boundaries and profile identifiers.

## Topics

- ``XcodeCacheSession``
- ``XcodeCachePrefixMapping``
- ``XcodeCacheServerError``
- ``XcodeServeRunner``
- ``XcodeServeHandle``
- ``X8Doctor``
- ``X8CacheStatsRunner``
- <doc:Metrics>
- <doc:XcodeCompilationCaching>
- <doc:PrefixMapping>
- <doc:XcodeCacheRuntime>
- <doc:CacheAdministration>
- <doc:Launchd>
