# Creating a custom CLI

Reuse x8's commands while supplying your own storage and configuration.

## Choose the reusable surface

Use `X8CLI` when you want the same `xcodebuild`, `serve`, `config`, `doctor`,
and `cache purge` interface as the official executable. Use `X8Kit` directly
when you are designing a different interface or embedding the cache server in
an existing application.

The official `x8` binary continues to support S3-compatible storage only.
Installing a separate storage package does not add storage choices to that binary.

## Add the library products

Add the X8 package to your executable's SwiftPM dependencies with the `S3`
trait disabled. Add the `X8CLI` and `X8Storage` products to your executable
target, plus `X8Core` if your storage implementation uses its domain types.
Your own provider SDK remains a dependency of your storage implementation.

The [complete example package](https://github.com/Ryu0118/x8/tree/main/Examples/CustomStorageCLI)
uses a local X8 dependency so it can be built against unreleased source. In a
separate repository, use a released version of the X8 GitHub package instead.

## Connect your implementation

The example's executable has this entire entry point:

```swift
import X8CLI

@main
struct ExampleCache {
    static func main() async {
        let cli = X8CLI(
            configuration: ExampleConfiguration.load,
            storage: { _ in ExampleMemoryStorage() }
        )
        await cli.main()
    }
}
```

`ExampleConfiguration` and `ExampleMemoryStorage` are supplied by the example
package, not by X8. Replace them with your own configuration and storage types.
The storage factory receives the exact `value` returned by your configuration
loader. A factory that needs it can use `storage: { MyStorage(configuration: $0) }`.
The configuration closure is `async throws`, so filesystem or network-backed
configuration loading can remain on the same async path as storage creation.

Your storage must conform to both `CASStore` and `ActionCacheStore`. No
additional CLI-specific conformance is required. If the client needs cleanup,
pass `shutdown: { try await $0.shutdown() }`.

## Exercise the example

From `Examples/CustomStorageCLI`:

```sh
swift run ExampleCache --help
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache config show
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache doctor
EXAMPLE_CACHE_DOMAIN=demo swift run ExampleCache serve --print-cache-settings
```

The example deliberately uses bounded in-memory storage. Records disappear on
exit; it is not a persistent or remote cache. It omits administrative capabilities,
so `cache purge` reports that administration is unsupported.

`main()` exits with the command's status after cleanup. For tests or repeated
invocations inside a host process, use `await cli.run(arguments: [...])`; it
returns an `Int32` status without calling `exit`. The command tree, including
the `x8` name in usage text, is shared with the official executable.

X8CLI has no S3 or YAML compilation dependency. SwiftPM may still fetch
packages that belong to other products; the example README describes how to
check downloads separately from the target dependency graph.
