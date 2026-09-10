# Custom storage, shared CLI

This is a complete, independent Swift package that builds `ExampleCache`: an
executable with the same `serve`, `doctor`, `config`, and `cache purge`
commands as the official `x8`, but backed by a storage implementation of its
own instead of S3. It shows what a custom storage backend needs to supply and
what it gets for free from the **X8CLI** library.

The package consumes only X8's public library APIs. It does not enable the
`S3` trait, import X8Config, or read `.x8.yml`. Three source files make up
the executable, under `Sources/ExampleCache/`:

- `ExampleCache.swift` — the `@main` entry point; it hands a configuration
  loader and a storage factory to `X8CLI` and calls `main()`.
- `ExampleConfiguration.swift` — the configuration loader. Instead of a YAML
  file it reads one environment variable, `EXAMPLE_CACHE_DOMAIN`, whose value
  is an arbitrary label that names the cache this process serves (it is
  hashed into the profile ID, and therefore the socket path, so two domains
  never share a socket). Your executable can define its own files and
  authentication scheme here.
- `ExampleMemoryStorage.swift` — the storage backend.

From this directory:

```sh
swift run ExampleCache --help
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache config validate
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache config show
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache doctor
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache serve --print-cache-settings
```

The example deliberately stores data in memory. It keeps at most 128 CAS
records (the content-addressed compiled objects) and 128 Action Cache records
(the index that maps a compile step to those objects), with a 1 MiB payload
limit per record. Data disappears when the process stops. It is not a
persistent or remote cache and does not implement administrative operations;
`cache purge` therefore fails with an explicit unsupported-capability
diagnostic.

Replace `ExampleMemoryStorage` with your own `CASStore` and `ActionCacheStore`
implementation, and pass a `shutdown:` closure if it owns resources that need
asynchronous cleanup. No CLI-specific storage protocol is required.

The local package dependency points at the repository root, since this
example lives inside the X8 repository. In your own project, depend on a
released version of `https://github.com/Ryu0118/x8.git` instead.

One SwiftPM detail worth knowing: the X8 package declares Soto and Yams for
its S3 and YAML products, and SwiftPM fetches every declared package during
resolution even when your target links none of them. The fetched packages do
not end up in your binary, but if you want to confirm that (or avoid the
download), build with `--experimental-prune-unused-dependencies`, which skips
packages no target in the graph uses. `scripts/check-custom-cli.sh` at the
repository root is the check CI runs: it builds this example that way and
asserts that no `X8Config`, `X8S3`, `Yams`, or Soto module was produced.
