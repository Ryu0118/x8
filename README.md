# 🗄️ x8

**An S3-compatible remote compilation cache proxy for Xcode.**

[![Test](https://github.com/Ryu0118/x8/actions/workflows/test.yml/badge.svg)](https://github.com/Ryu0118/x8/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

Xcode already caches compiled Swift/Clang modules, but that cache lives on
each machine: a module built on one Mac is built again on every other Mac and
CI runner. x8 lets a team share one cache instead. It speaks Xcode's cache
protocol over a local Unix domain socket and stores the cached objects in AWS
S3, Cloudflare R2, or any other S3-compatible bucket, so whatever one machine
compiles, every other machine can download instead of rebuilding.

## Features

- 🚝 **Shared remote cache:** Share one compilation cache with your team across
  Macs and CI runners instead of rebuilding the same modules everywhere.
- ⚙️ **Drop-in `xcodebuild` proxy:** Wrap `xcodebuild` with `x8 xcodebuild`, or
  run a standalone proxy with `x8 serve` for Xcode.app GUI builds.
- 🔌 **Any S3-compatible provider:** AWS S3, Cloudflare R2, MinIO, or another
  provider, without backend lock-in.

## Table of Contents

- [How it works](#how-it-works)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Enabling the remote cache](#enabling-the-remote-cache)
  - [`xcodebuild`](#1-xcodebuild)
  - [Xcode.app GUI builds](#2-xcodeapp-gui-builds)
- [Configuration](#configuration)
- [Commands](#commands)
- [Using another storage implementation](#using-another-storage-implementation)
- [Documentation](#documentation)
- [License](#license)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="asset/how-it-works~dark.svg">
  <img alt="xcodebuild or Xcode.app talks the Compilation Cache protocol over a Unix socket to the x8 proxy, which reads and writes objects in an S3-compatible bucket" src="asset/how-it-works.svg">
</picture>

A handful of build settings point Xcode's Compilation Cache plugin at a local
socket. x8 listens on that socket, speaks the gRPC protocol the plugin
expects, and translates each cache lookup or upload into a read or write of
one object in your bucket using an S3 `GetObject` or `PutObject` request. That
is why any S3-compatible provider works.

## Installation

x8 needs Xcode 27 or later (which itself requires macOS 26) and an
S3-compatible bucket such as AWS S3, Cloudflare R2, or MinIO. That is all you
need to get started.

### Nest ([mtj0928/nest](https://github.com/mtj0928/nest))

```sh
nest install Ryu0118/x8
```

### Mise ([jdx/mise](https://github.com/jdx/mise))

```sh
mise use -g github:Ryu0118/x8
```

## Quick Start

1. Create `.x8.yml` at your project root. For AWS S3, the bucket name is enough:

   ```yaml
   version: 1
   s3:
     api:
       bucket: my-team-cache
       credentials:
         source: defaultChain
     read: api
     write: api
   ```

   For Cloudflare R2, add its S3 endpoint and signing region. Replace
   `YOUR_ACCOUNT_ID` with your Cloudflare account ID. See [Cloudflare's R2 S3
   API guide](https://developers.cloudflare.com/r2/api/s3/api/) for endpoint
   and credential setup details:

   ```yaml
   version: 1
   s3:
     api:
       bucket: my-team-cache
       region: auto
       endpoint: https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
       credentials:
         source: static
         accessKeyID: ${AWS_ACCESS_KEY_ID}
         secretAccessKey: ${AWS_SECRET_ACCESS_KEY}
     read: api
     write: api
   ```

2. Provide credentials. `source: defaultChain` uses your existing AWS setup
   (for example `aws configure` or `aws sso login`). To use explicit keys
   instead, such as R2 API tokens, set `credentials` to `static` and pass the
   values through environment variables:

   ```yaml
   s3:
     api:
       # bucket, endpoint, ...
       credentials:
         source: static
         accessKeyID: ${AWS_ACCESS_KEY_ID}
         secretAccessKey: ${AWS_SECRET_ACCESS_KEY}
   ```

   Never commit a literal secret value. See [Configuring x8 with
   .x8.yml](https://ryu0118.github.io/x8/documentation/x8config/configurationfile)
   for every option.

3. Confirm everything is wired up:

   ```sh
   x8 doctor
   ```

4. Build through the proxy:

   ```sh
   x8 xcodebuild -workspace MyApp.xcworkspace -scheme MyApp build
   ```

   That's all a command-line build needs. Building from Xcode.app uses a
   long-running `x8 serve` plus a few build settings. See [Xcode.app GUI
   builds](#2-xcodeapp-gui-builds) below.

## Enabling the remote cache

There are two ways to point Xcode at x8's socket, depending on how you build.
For command-line builds, `x8 xcodebuild` supplies the cache connection and
prefix-mapping settings without changing build paths. For Xcode.app builds,
configure the printed cache settings in the project or an `.xcconfig`.

### 1. `xcodebuild`

Wraps a normal `xcodebuild` invocation with an embedded, invocation-scoped
proxy. No `.xcconfig` or `project.pbxproj` edits required:

```sh
x8 xcodebuild -workspace MyApp.xcworkspace -scheme MyApp build
```

Pass `xcodebuild`, or an absolute path ending in `xcodebuild` (for a specific
Xcode.app), as the first argument; everything after it is forwarded to that
executable unchanged. x8 preserves the caller's build arguments and chosen
directories.

x8 also makes the build portable across machines through *prefix mapping*,
so a module built on your Mac can still be a cache hit on another machine.
Pass `--no-prefix-mapping` (before the child `xcodebuild` argument) if your
project already handles build-path portability itself. See
[Prefix mapping](Sources/X8Kit/X8Kit.docc/PrefixMapping.md) for details.

### 2. Xcode.app GUI builds

Xcode's GUI builds can't be wrapped, so they need the settings Xcode's
Compilation Cache plugin looks for, added directly to your target (or an
`.xcconfig`) as **user-defined build settings** (they aren't exposed in
Xcode's Build Settings UI, so add them by name). Together they tell Xcode to
send cache traffic to x8's socket and to record build paths as portable
`/^…` placeholders instead of machine-specific absolute paths, so cache
entries match across machines.

Start the long-lived proxy; it prints the exact `SETTING=VALUE` pairs to add,
so you don't need to understand prefix mapping to use them. Run it from the
project directory containing `.x8.yml`; `--workspace-directory` only matters
when the Xcode workspace root is a different directory from where `.x8.yml`
lives:

```sh
x8 serve --workspace-directory /path/to/workspace
```

```text
CLANG_ENABLE_PREFIX_MAPPING=YES
CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES
CLANG_MODULES_BUILD_SESSION_FILE=
CLANG_OTHER_PREFIX_MAPPINGS=$(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built $(OBJROOT)/../..=/^dd /path/to/workspace=/^workspace
COMPILATION_CACHE_ENABLE_CACHING=YES
COMPILATION_CACHE_ENABLE_PLUGIN=YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH=/Users/you/Library/Application Support/X8/<profile-id>/cache.sock
SWIFT_ENABLE_PREFIX_MAPPING=YES
SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES
SWIFT_OTHER_PREFIX_MAPPINGS=$(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built $(OBJROOT)/../..=/^dd /path/to/workspace=/^workspace
```

Copy each line into your target's (or `.xcconfig`'s) user-defined build
settings exactly as printed. Keep `x8 serve` running so Xcode always has a
socket to connect to, then build from Xcode.app as usual. Use the same
logical `/^workspace` replacement on every machine; neither mode relocates
build outputs.

Run `x8 serve -d` (or `--detach`) instead to start the proxy in the
background and return once it is ready, printing the same cache settings
above (or, with `--print-socket`, only the socket path):

```sh
x8 serve -d --workspace-directory /path/to/workspace
```

The detached process keeps running after the terminal closes; its stdout and
stderr go to a `serve.log` next to its socket (rotated to `serve.log.1` on the
next `-d`). Stop it with:

```sh
x8 serve stop
```

`stop` sends a graceful shutdown signal, waits briefly, force-kills if it does
not exit, and removes its socket and process-record files. It reports success
even if no detached process was running for the current profile.

> [!WARNING]
> With local SwiftPM package dependencies, these settings only reach targets
> defined directly in your `.xcodeproj`. Xcode's `swift-build` engine does not
> propagate project settings to synthesized package targets, so those targets
> remain uncached in GUI builds. This does not affect apps without local
> package dependencies or builds through `x8 xcodebuild`. See
> [Known limitation: GUI builds with SwiftPM multi-module targets](Sources/X8Kit/X8Kit.docc/PrefixMapping.md#known-limitation-gui-builds-with-swiftpm-multi-module-targets-dont-propagate-user-defined-settings-to-package-targets)
> for details.

## Watching live cache traffic

`x8 tail` subscribes to the live cache-events socket and prints cache
requests as they happen. Run it in another terminal from the project root
while `x8 xcodebuild` is running. `x8 serve` prints its own live traffic in
the terminal where it runs.

## Configuration

x8 reads `.x8.yml` from the project root and an optional, git-ignored
`.x8.local.yml` overlay beside it. `s3.read` and `s3.write` choose how each
machine reads and writes the cache: `api` (signed S3 API), `publicURL` (reads
only, no credentials), or `none`. Every value supports `$VAR` expansion.

See [Configuring x8 with .x8.yml](https://ryu0118.github.io/x8/documentation/x8config/configurationfile) for every key, local overlays, reading
from a public URL without credentials, and pinning the socket path.

## Commands

| Command | Purpose |
| --- | --- |
| `x8 [xcodebuild] <xcodebuild> [args...]` | Run `xcodebuild` through an embedded, invocation-scoped cache proxy. |
| `x8 serve` | Run a standalone proxy at a stable socket, for Xcode's GUI or a supervised long-lived process. |
| `x8 serve --socket-path <path>` | Pin the socket to a fixed path for this invocation, overriding `.x8.yml`'s `socketPath` and the per-user default. |
| `x8 serve -d` / `--detach` | Run the standalone proxy in the background and return once it is ready. |
| `x8 serve stop` / `x8 serve stop --socket-path <path>` | Stop a detached `x8 serve -d` process for the current profile, or one pinned to a fixed socket path. |
| `x8 tail` / `x8 tail --socket-path <path>` | Stream live cache traffic from a running `x8 serve` or `x8 xcodebuild` invocation, or one pinned to a fixed socket path. |
| `x8 config validate` | Validate `.x8.yml` and its resolved values. |
| `x8 config show` | Print resolved, non-secret configuration. |
| `x8 doctor` | Check configuration, storage access, and the local proxy in one pass. |
| `x8 cache purge` | Plan or delete aged staging/Action Cache objects, or unreachable CAS objects. |

Run `x8 help <subcommand>` for full flag documentation. `cache purge`'s
`--older-than` and `--grace-period` accept a number followed by `ms`, `s`,
`m`, `h`, or `d` (for example `30m`, `2h`, or `7d`).

## Using another storage implementation

The official `x8` executable supports S3-compatible storage only. To use another
storage implementation, such as one you write for GCS or Azure, build your own
executable with the **X8CLI** library. It provides the same command definitions,
argument handling, and execution behavior:

```swift
let cli = X8CLI(
    configuration: loadConfiguration,
    storage: { MyStorage(configuration: $0) },
    shutdown: { try await $0.shutdown() }
)
await cli.main()
```

Supply your own configuration loader and a storage type conforming to
`CASStore` and `ActionCacheStore`. No CLI-specific storage protocol is required.
The configuration loader is an `async throws` closure, so loading configuration
and opening storage share one async execution path.
Your executable owns its configuration format and authentication; `.x8.yml`
and its S3 schema remain specific to the official executable. Administrative
commands additionally require the corresponding X8Storage capabilities.

Start with the [custom CLI guide](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli/)
and the [complete example package](Examples/CustomStorageCLI).

## Documentation

Full API documentation is published at
[ryu0118.github.io/x8/documentation/x8cli](https://ryu0118.github.io/x8/documentation/x8cli/).

- [Configuring x8 with .x8.yml](https://ryu0118.github.io/x8/documentation/x8config/configurationfile)
  lists every `.x8.yml`/`.x8.local.yml` key and covers overlays, credential-free
  public-URL reads, and the socket path.
- [Prefix mapping](https://ryu0118.github.io/x8/documentation/x8kit/prefixmapping)
  explains how build paths are made portable across machines, the toolchain
  requirement, and the known limitations. Read it when cache hits are lower
  than expected or a build shape doesn't seem to cache.
- [Creating a custom CLI](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli/)
  walks through building an executable on another storage backend. Read it
  only if you need a non-S3 backend.

## License

x8 is available under the MIT License. See [LICENSE](LICENSE) for details.
