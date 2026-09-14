# 🗄️ x8

**An S3-compatible remote compilation cache proxy for Xcode.**

[![Test](https://github.com/Ryu0118/x8/actions/workflows/test.yml/badge.svg)](https://github.com/Ryu0118/x8/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.1-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

**[Full API documentation →](https://ryu0118.github.io/x8/documentation/x8kit/)**

Xcode already caches compiled Swift/Clang modules, but that cache lives on
each machine: a module built on one Mac is built again on every other Mac and
CI runner. x8 lets a team share one cache instead. It speaks Xcode's cache
protocol over a local Unix domain socket and stores the cached objects in AWS
S3, Cloudflare R2, or any other S3-compatible bucket, so whatever one machine
compiles, every other machine can download instead of rebuilding.

🚝 **Shared remote cache:** One compilation cache across every Mac and CI
runner instead of rebuilding the same modules everywhere.
⚙️ **Drop-in `xcodebuild` proxy:** Wrap `xcodebuild` with `x8 xcodebuild`, or
run a standalone proxy with `x8 serve` for Xcode.app GUI builds.
🔌 **Any S3-compatible provider:** AWS S3, Cloudflare R2, MinIO, or your own —
no backend lock-in.

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
  <source media="(prefers-color-scheme: dark)" srcset="Diagrams/how-it-works~dark.svg">
  <img alt="xcodebuild or Xcode.app talks the Compilation Cache protocol over a Unix socket to the x8 proxy, which reads and writes objects in an S3-compatible bucket" src="Diagrams/how-it-works.svg">
</picture>

A handful of build settings point Xcode's Compilation Cache plugin at a local
socket. x8 listens on that socket, speaks the gRPC protocol the plugin
expects, and translates each cache lookup or upload into a read or write of
one object in your bucket (an S3 `GetObject` or `PutObject` request, which is
why any S3-compatible provider works).

## Installation

x8 needs Xcode 27 or later (which itself requires macOS 26) and an
S3-compatible bucket — AWS S3, Cloudflare R2, MinIO, or similar. That is all
you need to get started. Xcode 26 is unsupported because it crashes on cached,
prefix-mapped builds; the
[Toolchain support](Sources/X8Kit/X8Kit.docc/PrefixMapping.md#toolchain-support)
note has the details if you are curious, but you don't need to read it now.

### Nest ([mtj0928/nest](https://github.com/mtj0928/nest))

```sh
nest install Ryu0118/x8
```

### Mise ([jdx/mise](https://github.com/jdx/mise))

```sh
mise use -g github:Ryu0118/x8
```

## Quick Start

1. Create `.x8.yml` at your project root:

   ```yaml
   version: 1
   bucket: my-team-cache
   # endpoint is optional for AWS S3 — omit it entirely and x8 uses AWS's
   # default endpoint. Set it only for an S3-compatible provider. For R2,
   # replace abc123 with your Cloudflare account ID (shown in the R2
   # dashboard next to the bucket's S3 API URL):
   endpoint: https://abc123.r2.cloudflarestorage.com
   ```

2. Provide credentials. Every field in `.x8.yml` supports POSIX-style
   `$VAR`/`${VAR}` expansion against the process environment, so static
   credentials can be committed by reference:

   ```yaml
   accessKeyID: ${AWS_ACCESS_KEY_ID}
   secretAccessKey: ${AWS_SECRET_ACCESS_KEY}
   ```

   Without static credentials, x8 uses the standard AWS credential provider
   chain (environment, shared config file, SSO, `AssumeRole`,
   container/instance metadata) — nothing to configure. Never commit a
   *literal* secret value to `.x8.yml`; `$VAR` references are fine.

3. Confirm everything is wired up:

   ```sh
   x8 doctor
   ```

4. Build through the proxy:

   ```sh
   x8 xcodebuild -workspace MyApp.xcworkspace -scheme MyApp build
   ```

   That's all a command-line build needs. Building from Xcode.app
   instead uses a long-running `x8 serve` plus a few build settings — see
   [Xcode.app GUI builds](#2-xcodeapp-gui-builds) below.

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

While a build is running, `x8 tail` (run from another terminal in the same
project) streams that invocation's cache traffic, the same as it would for
`x8 serve`. `x8 serve` also prints its own live cache traffic inline while it
runs, so a standalone proxy needs no separate `x8 tail` to watch it. See
[Watching live cache traffic](#watching-live-cache-traffic) for how the two
relate when both are running at once.

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
background and return once it is ready, printing only the socket path:

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

## Watching live cache traffic

`x8 tail` connects to a live cache-events socket and prints each cache
request as it happens. Both `x8 serve` and `x8 xcodebuild` open this socket,
so `x8 tail` works against either — there is nothing else to configure.
`x8 serve` streams the same traffic to its own terminal directly, without
dialing that socket, so it stays visible even if the socket fails to bind.

The socket's identity comes from the *profile ID*, a hash of `.x8.yml`'s
`version`, `endpoint`, `region`, and `bucket`, not from the directory you run
x8 in. Two projects pointed at the same bucket/endpoint/region share one
profile ID and one events socket; the same project run from two different
directories also shares it. This is why `x8 tail` needs no arguments to find
the right socket: it derives the same profile ID from the current directory's
`.x8.yml` and connects to the matching path.

Only one process can own the events socket for a given profile ID at a time.
Binding is fail-open and attempted once, at startup: whichever of `x8 serve`
or `x8 xcodebuild` starts first keeps the socket for its entire run, and the
other's cache traffic stays invisible to `x8 tail` for that whole run, even
after the first process exits and frees the socket. If you run both against
the same profile — for example, a long-lived `x8 serve` alongside an
`x8 xcodebuild` invocation for the same project — start `x8 serve` first so
`x8 tail` can observe both.

## Configuration

x8 reads `.x8.yml` from the project root; it is the file every machine shares,
so commit it. An optional, git-ignored `.x8.local.yml` next to it overlays
values for whichever machine it lives on: use it only when a value is
genuinely machine-specific rather than something every clone of the repo
should share. Every key below can appear in either file, and every value
supports `$VAR` expansion.

| Key | Required | Description |
| --- | --- | --- |
| `version` | yes | Config schema version. Currently `1`. |
| `bucket` | yes | The S3 bucket name. |
| `region` | no | AWS region or provider-specific signing region. Defaults to `us-east-1`. |
| `endpoint` | no | Custom endpoint for an S3-compatible provider (e.g. R2). Omit for AWS S3. |
| `role` | no | What this machine may do with the cache: `producer` (write only — uploads, never downloads), `consumer` (read only — downloads, never uploads), or `both` (read and write). Defaults to `both`. |
| `accessKeyID` | no | Static access key ID. Omit to use the standard AWS credential provider chain. |
| `secretAccessKey` | no | Static secret access key, paired with `accessKeyID`. Never commit a literal value — use `$VAR` expansion. |
| `sessionToken` | no | Optional session token for temporary/STS credentials, paired with `accessKeyID`/`secretAccessKey`. |

`role` is enforced at the storage boundary: a producer's reads return cache
misses without contacting storage, and a consumer's writes are rejected before
reaching storage. The role does not change where the cache lives, so a producer
job and a consumer laptop reading the same `.x8.yml` still share the same cache.
A single shared `role: both` in `.x8.yml` is often enough. Split it into
`.x8.local.yml` overlays only when specific machines need to be restricted —
typically CI runners that populate the cache as `producer` and developer
machines that only pull from it as `consumer`:

```yaml
# .x8.local.yml on a CI runner
role: producer
```

```yaml
# .x8.local.yml on a developer's laptop
role: consumer
```

## Commands

| Command | Purpose |
| --- | --- |
| `x8 [xcodebuild] <xcodebuild> [args...]` | Run `xcodebuild` through an embedded, invocation-scoped cache proxy. |
| `x8 serve` | Run a standalone proxy at a stable socket, for Xcode's GUI or a supervised long-lived process. |
| `x8 serve -d` / `--detach` | Run the standalone proxy in the background and return once it is ready. |
| `x8 serve stop` | Stop a detached `x8 serve -d` process for the current profile. |
| `x8 tail` | Stream live cache traffic from a running `x8 serve` or `x8 xcodebuild` invocation. |
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

- [Prefix mapping](https://ryu0118.github.io/x8/documentation/x8kit/prefixmapping)
  explains how build paths are made portable across machines, the toolchain
  requirement, and the known limitations. Read it when cache hits are lower
  than expected or a build shape doesn't seem to cache.
- [Creating a custom CLI](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli/)
  walks through building an executable on another storage backend. Read it
  only if you need a non-S3 backend.

## License

x8 is available under the MIT License. See [LICENSE](LICENSE) for details.
