# Prefix mapping and cache portability

Prefix mapping replaces the physical checkout, DerivedData, and product
paths in a compiler job with stable logical prefixes before Xcode computes
the job's cache key, so the same source compiled in two checkouts can share
one cache entry. X8 emits the six Swift and Clang prefix-mapping settings and
an empty module-validation session path alongside the three connection
settings; `x8 xcodebuild` injects them, and `x8 serve --print-cache-settings`
prints them for Xcode.app.

Xcode keys a compiler job on its arguments and other inputs, not just the
source bytes, so mapping the working directory is necessary but not
sufficient: cross-worktree reuse still depends on the toolchain and on
generated inputs such as macro plugin executables (see the known limitations
below).

## Normalizing paths without breaking output resolution

Portable keys require equivalent inputs to use the same logical path before
hashing. Diagnostics, debug information, generated metadata, and other outputs
must then resolve correctly in the consuming checkout. Normalizing a key
without handling those outputs is not sufficient.

X8 preserves the caller's `-derivedDataPath`, package checkout path, and
build-output settings. It does not add fixed directories or change batching.
An explicitly supplied DerivedData path is used only to stage disk-backed CAS
responses on the same volume, because the Xcode plugin links response files
into its local cache. When the argument is absent, X8 leaves Xcode's location
selection alone and uses the session's normal response directory.

## Current prefix settings

The cache environment includes three `COMPILATION_CACHE_*` connection
settings, six prefix-mapping settings, and a module-validation setting:

| Setting | Purpose |
| --- | --- |
| `SWIFT_ENABLE_PREFIX_MAPPING` | Enables Swift scanner mapping. |
| `CLANG_ENABLE_PREFIX_MAPPING` | Enables Clang dependency-scan mapping. |
| `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` | On Xcode 27+, maps project source, DerivedData, and product roots to logical prefixes. |
| `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` | The corresponding Clang project mapping on Xcode 27+. |
| `SWIFT_OTHER_PREFIX_MAPPINGS` | Supplies the explicit Swift mappings below. |
| `CLANG_OTHER_PREFIX_MAPPINGS` | Supplies the same mappings to Clang. |
| `CLANG_MODULES_BUILD_SESSION_FILE` | Empty: omits the once-per-session validation optimization whose physical path Swift does not remap. Normal module validation remains. |

```
$(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built $(OBJROOT)/../..=/^dd /actual/checkout=/^workspace
```

The `OBJROOT` entry reaches the DerivedData root only in Xcode's default
object-root layout. A custom `OBJROOT` can change what it covers. These maps
do not cover every compiler option, embedded path, or local source root.
`x8 xcodebuild` replaces `/actual/checkout` with the invocation's physical
working directory; `x8 serve` uses the current directory by default and
accepts `--workspace-directory` for a different Xcode client directory. The
mapping assigns a logical name; it does not relocate the workspace on disk.

The wrapper omits the six prefix settings and the session-file override when
`--no-prefix-mapping` precedes the child executable; the three connection
settings remain enabled. `serve --print-cache-settings` prints a literal
mapping for the current directory, or for the directory passed to
`--workspace-directory`, so the same command can configure Xcode.app on each
machine. When a target misses unexpectedly, the frontend command lines in the
build log show which mappings the toolchain applied to that job.

The mapping value is space-separated with no quoting or escaping, so a
working directory containing a space cannot be represented in it. X8 rejects
such a path before starting a server rather than emitting a mapping value
that would silently split into unrelated fragments; move the checkout to a
path without spaces, or pass `--no-prefix-mapping`.

## Known limitation: generated macro plugin executables

A Swift target that loads a macro plugin links that plugin as a Mach-O
executable with an embedded `LC_RPATH` load command containing the physical
build-output path (for example, `.../Build/Products/Debug/PackageFrameworks`).
Two checkouts with identical Swift source can therefore produce a
byte-different plugin executable, because the linked path differs between
checkouts.

Prefix mapping only normalizes paths used while scanning the plugin; it
cannot retroactively rewrite the linked plugin binary's embedded path.
Different plugin bytes produce a different CAS identity for that dependency
scanner input, so a target that loads such a plugin can see a Swift compile
key that differs between two otherwise-identical checkouts:

```text
same Swift source
    + different generated macro executable
    = different Swift compile key
    = SwiftCompile cache miss
```

This is not an X8 defect or an LLVM CAS object-corruption case; the Swift
dependency scanner treats a macro plugin library as a CAS input, so unchanged
source bytes do not imply an unchanged Swift compile key. The Swift Forums
investigation describes the same macro-plugin identity problem and proposes a
stable plugin identity instead of hashing the linked executable:
[compile-cache key instability from non-deterministic macro plugin binaries](https://forums.swift.org/t/compile-cache-key-instability-from-non-deterministic-macro-plugin-binaries/86695).

Swift [PR #80474](https://github.com/swiftlang/swift/pull/80474) (backported
as [PR #80751](https://github.com/swiftlang/swift/pull/80751)) makes
macro-plugin options cacheable when the plugin binary is identical and only
its location changes. It does not make two different plugin binaries
equivalent, so it does not by itself resolve this limitation.

## Known limitation: package trait ordering

Package traits are emitted as Swift `-D` condition flags in generated build
descriptions. If a target's frontend command differs only in the order of
these `-D` flags, that ordering alone changes its compile key and produces a
cache miss, even though the compiler inputs are otherwise identical. This is
a known hazard, not something X8's prefix mapping addresses, since prefix
mapping normalizes paths, not argument ordering.

## Known limitation: GUI builds with SwiftPM multi-module targets don't propagate user-defined settings to package targets

Xcode.app GUI builds add the cache settings from [Enabling the remote
cache](../../../../README.md#2-xcodeapp-gui-builds) as user-defined build
settings on a project or `.xcconfig`. Xcode's `swift-build` engine only
attaches a project's own `.xcconfig`/user-defined settings to that project's
*own* targets; it does not propagate them down into targets that belong to a
synthesized SwiftPM package project (a local Swift package your Xcode project
depends on, with its own `Package.swift`). Concretely: settings attached to
your `.xcodeproj`/`.xcworkspace` reach targets defined directly in that
`.xcodeproj`, but **not** targets inside a local Swift package pulled in as a
dependency — so the cache settings above never reach package targets, and
`COMPILATION_CACHE_*`/prefix-mapping never turns on for them. This is an
Xcode `swift-build` settings-propagation limitation that x8 cannot change
from outside Xcode.

Two ways this plays out in practice:

- **Xcode project has local SwiftPM package dependencies (multi-module app):**
  package targets do not see the cache settings from GUI builds, so they never
  get cached this way — only targets defined directly in the `.xcodeproj` do.
  `x8 xcodebuild` is unaffected, because it supplies the cache settings as CLI
  overrides (`xcodebuild ... OTHER_SWIFT_FLAGS=...`-style build setting
  overrides), and `swift-build` already applies CLI overrides to every target
  unconditionally, package targets included. If your project has SwiftPM
  package targets and you build from Xcode.app, expect fewer cache hits than
  the same build run through `x8 xcodebuild`.
- **Xcode project has no local SwiftPM package dependencies (all app code
  lives directly in Xcode targets):** this limitation does not apply — every
  target belongs to the `.xcodeproj` itself, so GUI builds cache normally.

## Toolchain support

Requires Xcode 27 or later; x8 does not check the Xcode version at runtime.
Xcode 26 crashes on cached, prefix-mapped batch diagnostics because the
compiler registered source buffers under the mapped path, where diagnostic
consumers could not find them. The Swift 6.4 fix
([swiftlang/swift#90700](https://github.com/swiftlang/swift/pull/90700))
registers them under the original path and ships in Xcode 27. The Swift 6.4
tools version in `Package.swift` describes building X8 itself, not the
supported Xcode client.
