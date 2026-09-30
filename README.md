# 🗄️ x8

**An S3-compatible remote compilation cache proxy for Xcode.**

[![Test](https://github.com/Ryu0118/x8/actions/workflows/test.yml/badge.svg)](https://github.com/Ryu0118/x8/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

Xcode's compilation cache normally stays on the machine that produced it. x8
lets Macs and CI runners share that cache through a local proxy and an
S3-compatible bucket. The official `x8` executable uses S3-compatible storage;
for another storage provider, build a separate executable with the `X8CLI`
library and your own storage adapter.

## Features

- 🚝 **Shared remote cache:** Share one compilation cache with your team across
  Macs and CI runners instead of rebuilding the same modules everywhere.
- ⚙️ **Drop-in `xcodebuild` proxy:** Wrap `xcodebuild` with `x8 xcodebuild`, or
  run a standalone proxy with `x8 serve` for Xcode.app GUI builds.
- 🔌 **Flexible storage:** Use S3-compatible storage with the official
  executable, or connect your own backend through `X8CLI`.

## Table of Contents

- [How it works](#how-it-works)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Custom storage](#custom-storage)
- [Enabling the remote cache](#enabling-the-remote-cache)
  - [`xcodebuild`](#1-xcodebuild)
  - [Xcode.app GUI builds](#2-xcodeapp-gui-builds)
- [Configuration](#configuration)
- [Commands](#commands)
- [License](#license)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="asset/how-it-works~dark.svg">
  <img alt="xcodebuild or Xcode.app talks the Compilation Cache protocol over a Unix socket to the x8 proxy, which reads and writes objects in an S3-compatible bucket" src="asset/how-it-works.svg">
</picture>

Xcode's Compilation Cache plugin connects to a local socket served by x8. The
official executable stores cache records in an S3-compatible bucket. A custom
executable can use the same commands with an adapter for another provider.

## Installation

The official `x8` executable needs Xcode 27 or later (on macOS 26 or later) and
an S3-compatible bucket such as AWS S3, Cloudflare R2, or MinIO. A custom
storage executable uses the provider you implement instead.

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

2. Provide credentials. `defaultChain` uses your existing AWS setup, including
   environment credentials, profiles, SSO, and supported role flows. For R2 or
   MinIO, use `static` credentials expanded from environment variables. Never
   commit secret values; see [Configuring x8 with
   .x8.yml](https://ryu0118.github.io/x8/documentation/configurationfile)
   for the complete schema.

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

## Custom storage

The official `x8` executable is S3-only; installing another provider package
does not add a backend to it. To cache through GCS, Azure Blob, a filesystem,
or another store, build your own executable with `X8CLI` and implement
`CASStore` plus `ActionCacheStore`. Your executable owns its configuration and
credentials. The [custom storage guide](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli)
covers package setup and storage injection; the [example package](Examples/CustomStorageCLI)
demonstrates the contracts with bounded in-memory storage.

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
Xcode.app), as the first argument. x8 forwards the remaining arguments and
preserves the caller's build directories.

x8 also makes the build portable across machines through *prefix mapping*,
so a module built on your Mac can still be a cache hit on another machine.
Pass `--no-prefix-mapping` (before the child `xcodebuild` argument) if your
project already handles build-path portability itself. See [Prefix mapping
and cache portability](https://ryu0118.github.io/x8/documentation/prefixmapping)
for supported cases and limitations.

### 2. Xcode.app GUI builds

Xcode's GUI builds can't be wrapped, so they need the settings Xcode's
Compilation Cache plugin looks for, added directly to your target (or an
`.xcconfig`) as **user-defined build settings** (they aren't exposed in
Xcode's Build Settings UI, so add them by name). Together they tell Xcode to
send cache traffic to x8's socket and to record build paths as portable
`/^…` placeholders instead of machine-specific absolute paths, so cache
entries match across machines.

Start the long-lived proxy from the directory containing `.x8.yml`. It prints
the `SETTING=VALUE` pairs to add. Use `--workspace-directory` when the Xcode
workspace root differs from the current directory:

```sh
x8 serve --workspace-directory /path/to/workspace
```

Copy the printed lines into the target's or `.xcconfig`'s user-defined build
settings. Keep `x8 serve` running while building from Xcode.app. Use the same
logical workspace prefix on every machine.

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
> [Prefix mapping and cache portability](https://ryu0118.github.io/x8/documentation/prefixmapping)
> for the affected GUI builds and the command-line alternative.

## Configuration

x8 reads `.x8.yml` from the project root and an optional, git-ignored
`.x8.local.yml` overlay beside it. `s3.read` and `s3.write` choose how each
machine reads and writes the cache: `api` (signed S3 API), `publicURL` (reads
only, no credentials), or `none`. Every value supports `$VAR` expansion.

See [Configuring x8 with .x8.yml](https://ryu0118.github.io/x8/documentation/configurationfile) for every key, local overlays, reading
from a public URL without credentials, and pinning the socket path.

## Commands

| Command | Purpose |
| --- | --- |
| `x8 [xcodebuild] <xcodebuild> [args...]` | Run `xcodebuild` through an embedded, invocation-scoped cache proxy. |
| `x8 serve` | Run the proxy for Xcode.app builds. Add `-d` to detach it. |
| `x8 serve stop` | Stop a detached proxy. |
| `x8 tail` | Stream cache traffic from a running proxy. |
| `x8 config validate` / `show` | Validate or print resolved, non-secret configuration. |
| `x8 doctor` | Check configuration, storage access, and the local proxy. |
| `x8 cache purge` | Plan and optionally delete eligible cache records. |

Run `x8 help <subcommand>` for the full flag reference. Browse the [published
documentation](https://ryu0118.github.io/x8/documentation/x8cli/) for API and
configuration guides.

## License

x8 is available under the MIT License. See [LICENSE](LICENSE) for details.
