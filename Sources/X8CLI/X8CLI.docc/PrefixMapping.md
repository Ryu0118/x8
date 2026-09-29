# Prefix mapping and cache portability

Xcode includes file paths in compilation-cache keys. Prefix mapping replaces
common checkout, DerivedData, and product paths in those keys with stable
logical paths so equivalent builds from different checkouts can share results.
It does not move build outputs or change your build directories.

## Command-line and Xcode.app builds

`x8 xcodebuild` adds the cache connection and prefix-mapping settings for each
invocation. Put `--no-prefix-mapping` before the `xcodebuild` argument if your
project already makes build paths portable; cache connection remains enabled.

Xcode.app builds need a long-running `x8 serve`. Copy the settings it prints
into the target's or `.xcconfig`'s user-defined build settings. Use the same
logical workspace prefix on every machine, and pass `--workspace-directory`
when the workspace is not in the current directory.

## Requirements and limits

Use Xcode 27 or later. Xcode 26 has a compiler issue with cached,
prefix-mapped batch diagnostics. The Swift tools version in X8's `Package.swift`
is the version needed to build X8; the Xcode version is the client requirement.

The mapping format is space-separated and cannot represent a checkout path
that contains spaces. Move the checkout to a path without spaces or use
`--no-prefix-mapping`.

Path mapping removes only path differences. The toolchain, compiler arguments,
and generated inputs still need to match for two builds to share an entry.
Macro-plugin binaries can embed build paths, and SwiftPM trait flags can appear
in a different order; either difference can produce a cache miss.

For Xcode.app builds, user-defined settings reach targets in the Xcode project
but do not propagate to targets in local SwiftPM packages. Those package
targets remain uncached in GUI builds. `x8 xcodebuild` supplies settings as
command-line overrides, which also reach package targets.
