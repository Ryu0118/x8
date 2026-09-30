# Set up the X8 cache for Xcode

X8 runs a small cache service on the same Mac as Xcode. Xcode connects to that
service; X8 reads and writes cache data using the storage configured for your
project. The connection is local to the Mac. The configured storage determines
which machines can share results.

There are two ways to run X8. Use `x8 xcodebuild` for builds started in
Terminal. Use `x8 serve` when you build from Xcode.app.

## Before you start

Run X8 from the project directory containing `.x8.yml`. X8 reads that file
from its current directory. An optional, ignored `.x8.local.yml` can hold
machine-specific credentials or read/write settings. See [Configuring x8 with
.x8.yml](https://ryu0118.github.io/x8/documentation/configurationfile) for
storage and credential examples.

Check the configuration and storage connection with:

```sh
x8 doctor
```

The official `x8` executable uses S3-compatible storage. To use another
provider, create a separate executable with `X8CLI`; see the [custom storage
guide](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli).

## Builds from Terminal

Use `x8 xcodebuild` in place of `xcodebuild`:

```sh
x8 xcodebuild -workspace MyApp.xcworkspace -scheme MyApp build
```

X8 starts a private cache service for this build, passes the cache settings to
`xcodebuild`, waits for the build to finish, and then shuts the service down.
You do not need to run `x8 serve` or edit the Xcode project. X8 forwards the
normal `xcodebuild` arguments and preserves build paths such as
`-derivedDataPath`.

X8 also enables prefix mapping by default. This replaces common machine-local
checkout and DerivedData paths with shared logical paths, which helps builds
on different Macs find the same cache entries. If your project already sets
its own prefix mappings, put `--no-prefix-mapping` before `xcodebuild`:

```sh
x8 --no-prefix-mapping xcodebuild -workspace MyApp.xcworkspace -scheme MyApp build
```

Use an absolute path to `xcodebuild` as the first argument when you need to
build with a specific Xcode installation. See [Prefix mapping and cache
portability](https://ryu0118.github.io/x8/documentation/prefixmapping) for
requirements and limits.

## Builds from Xcode.app

Xcode.app cannot be wrapped in `x8 xcodebuild`, so it connects to a separate
X8 service that stays running while you build.

1. In Terminal, go to the directory containing `.x8.yml` and start the
   service. If the workspace is elsewhere, give its full path to
   `--workspace-directory`:

   ```sh
   x8 serve --workspace-directory /path/to/MyApp
   ```

   `--workspace-directory` selects the checkout path used by prefix mapping;
   it does not change where X8 reads `.x8.yml`.

2. X8 prints the settings Xcode needs. Add every printed `NAME=VALUE` as a
   user-defined build setting on the app target or in an `.xcconfig`. Xcode
   does not read these from the Terminal environment. The settings enable its
   compilation cache, point it to the local X8 service, and make common build
   paths consistent. Copy the complete output instead of recreating the
   settings by hand.

3. Keep the foreground `x8 serve` running while you build. Press Control-C
   when you are done. To run it in the background, start it with `x8 serve -d`
   and stop it later with `x8 serve stop`.

The printed socket path and checkout path belong to that Mac. Generate the
settings on each machine and use a local `.xcconfig` when those paths differ;
keep the logical workspace prefix the same on every machine. If you choose a
custom `socketPath` in `.x8.yml` or pass `--socket-path`, use that same path
when stopping the server. See [Pinning the socket path](https://ryu0118.github.io/x8/documentation/configurationfile#pinning-the-socket-path).

## What gets shared

Xcode still uses its local DerivedData cache. X8 adds access to the remote
cache selected by your configuration; changing the local socket path does not
change that storage destination.

A cached result can be reused only when the compilation inputs match. The
source is one input; the Xcode version, compiler options, build settings, and
dependencies matter too. Prefix mapping normalizes common paths, but it cannot
make different compiler inputs equivalent. A cache miss is expected: Xcode
compiles the work locally. If the remote cache reports an error, X8 keeps the
build moving by letting Xcode compile locally. A machine only publishes new
results if its storage configuration allows writes.

For the default prefix-mapped setup, use Xcode 27 or later. Xcode.app settings
reach targets defined in the Xcode project, but do not propagate to targets in
local Swift packages. Those package targets use the cache when you build with
`x8 xcodebuild`, which passes settings directly to the build. The [prefix
mapping guide](https://ryu0118.github.io/x8/documentation/prefixmapping) has
the details and other portability limits.

## If builds do not reuse results

- Run `x8 doctor` from the project directory to check the configuration and
  storage access.
- For Xcode.app, check that `x8 serve` is still running and that the active
  target or `.xcconfig` has the settings printed by that Mac.
- For a cache miss across machines, compare the Xcode version, build settings,
  dependency inputs, and workspace mapping. The [prefix mapping
guide](https://ryu0118.github.io/x8/documentation/prefixmapping) explains
  which path differences X8 can normalize.
