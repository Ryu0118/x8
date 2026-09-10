# Custom storage, shared CLI

This independent Swift package consumes only X8's public library APIs. It
does not enable S3, import X8Config, or read `.x8.yml`. Its configuration comes
from `EXAMPLE_CACHE_DOMAIN`; another executable can define its own files and
authentication scheme.

From this directory:

```sh
swift run ExampleCache --help
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache config validate
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache config show
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache doctor
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache serve --print-cache-settings
```

The example deliberately stores data in memory. It keeps at most 128 CAS
records and 128 Action Cache records, with a 1 MiB payload limit per record.
Data disappears when the process stops. It is not a persistent or remote
cache and does not implement administrative operations; `cache purge`
therefore fails with an explicit unsupported-capability diagnostic.

Replace `ExampleMemoryStorage` with your own `CASStore` and `ActionCacheStore`
implementation, and pass a `shutdown:` closure if it owns resources that need
asynchronous cleanup. No CLI-specific storage protocol is required.

The local package dependency points at the repository root, since this
example lives inside the X8 repository. In your own project, depend on a
released version of `https://github.com/Ryu0118/x8.git` instead. When
verifying dependency downloads, use SwiftPM's
`--experimental-prune-unused-dependencies` option; target dependencies and
package fetching are separate concerns.
