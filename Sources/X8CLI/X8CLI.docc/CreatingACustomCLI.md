# Build an executable for custom storage

The official `x8` executable supports S3-compatible storage only. It has no
runtime backend plug-in. To cache in another service, build a separate Swift
executable with `X8CLI` and provide your own storage implementation.

## Add the package products

Add `X8CLI`, `X8Storage`, and `X8Core` to your executable target. Disable the
optional S3 trait so your executable does not build the official S3 adapter.
This repository has no tagged package releases yet, so the manifest below
uses the `main` branch; replace it with a release version when one is available.

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MyCache",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(
            url: "https://github.com/Ryu0118/x8.git",
            branch: "main",
            traits: []
        ),
    ],
    targets: [
        .executableTarget(
            name: "MyCache",
            dependencies: [
                .product(name: "X8CLI", package: "x8"),
                .product(name: "X8Storage", package: "x8"),
                .product(name: "X8Core", package: "x8"),
            ]
        ),
    ]
)
```

## Implement your provider adapter

Your storage type must conform to both ``CASStore`` and
``ActionCacheStore``. `CASStore` handles immutable CAS objects and their
references; `ActionCacheStore` stores opaque action keys and result values.
Preserve opaque identifiers, return `nil` only for confirmed misses, and keep
payloads streamed. See <doc:ImplementingStorage> for the contract details.

The shared CLI owns the command tree. Your executable owns the provider SDK,
configuration schema, and credentials. The configuration loader should read
and validate local settings; open the remote client in the storage factory.

## Connect configuration and storage

`configuration` returns `X8CLIConfiguration` with your typed settings in
`value`. Give each cache domain a stable, non-secret `profileID`; never put
credentials or signed URLs in `displayFields`, which `config show` prints.
The storage factory is asynchronous and receives that `value`:

```swift
let cli = X8CLI(
    configuration: MyConfiguration.load,
    storage: { settings in
        try await MyStorage.connect(settings)
    },
    shutdown: { try await $0.shutdown() }
)
await cli.main()
```

The CLI calls `shutdown` once after the command's storage work finishes. Pass
it when your adapter owns a client or other resource that needs asynchronous
cleanup. If constructing storage fails partway through, the factory must clean
up resources it created before throwing.

The official `.x8.yml` file and its S3 schema are not used by your executable.
Help and configuration-only commands do not open storage. For an embedded
host process, call `await cli.run(arguments:)`; it returns a status without
terminating the process.

## Optional administration

`CASStore` and `ActionCacheStore` are sufficient for Xcode cache reads and
writes. The shared command tree still contains `cache purge`; age-based purge
also needs ``CacheAdministration``, and reachability-based CAS purge additionally
needs ``CASReferenceReader`` and ``CASRetentionStore``. Implement these only
when your provider can satisfy their revision and retention guarantees.

## Run the example

The [complete example package](https://github.com/Ryu0118/x8/tree/main/Examples/CustomStorageCLI)
shows the manifest, configuration, and storage adapter. Its backend stores
bounded records in memory; data disappears when the process exits. Replace it
with a persistent provider for a shared remote cache.

```sh
cd Examples/CustomStorageCLI
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache doctor
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache serve --print-cache-settings
```
