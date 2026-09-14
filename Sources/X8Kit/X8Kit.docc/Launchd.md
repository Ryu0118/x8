# Launchd socket activation

``XcodeServeRunner/startActivated(socketName:)`` is the long-lived macOS path
for clients that need a stable cache endpoint, including Xcode GUI builds. A
LaunchAgent declares a `Sockets` entry named `Listener`; launchd creates and
binds the Unix socket, then X8 adopts the descriptor with
``X8LaunchdSocketActivation``.

This is different from ``XcodeCacheSession``, whose embedded proxy owns a
private invocation socket. In launchd mode, X8 never binds or removes the
socket node — launchd recreates it after a service restart, login, or
reboot. Cache records live in the configured storage backend, not the
socket, so none of that churn affects them.

`x8 launchd install` generates and bootstraps the LaunchAgent for you; this
article covers what it generates and how to manage or troubleshoot the
result. Its `WorkingDirectory` must contain `.x8.yml` — x8 reads the
configuration from the working directory only and does not search parents
— which `install` satisfies by running it from that directory.

## There is no `x8 stop`

launchd owns start, stop, and restart for this mode. x8 never binds or
removes the socket node, so it can't tear the service down either: killing
the x8 process just gets it relaunched on the next connection, since
launchd still holds the socket. Use `x8 launchd status` or `launchctl`
directly (below) for start, stop, restart, and status.

## Installing the LaunchAgent

Run from the directory containing `.x8.yml`:

```sh
x8 launchd install
```

This generates `~/Library/LaunchAgents/com.x8.<profile-id>.plist`, creates
the directories it needs, and bootstraps it with `launchctl`. The plist's
`Sockets.Listener.SockPathName` is always
``XcodeServeRunner/defaultSocketPath(profileID:)`` — the same path `x8 serve`
prints as `COMPILATION_CACHE_REMOTE_SERVICE_PATH` — so the two can never
disagree. `install` prints that path; put it in Xcode's build settings (see
below).

Pass `--workspace-directory` if the Xcode workspace root differs from the
directory containing `.x8.yml`, `--env KEY=VALUE` (repeatable) for anything
the storage backend needs (for example `AWS_PROFILE`; launchd does not
source your shell profile), and `--x8-path` if the running binary's path
cannot be resolved automatically (mise and nest shims usually resolve fine;
pass the absolute path from `which x8` if `install` asks for it).

`install` is safe to re-run: it boots out any existing service under the
same label before bootstrapping the new plist, so editing a build setting
you passed to `install` is just running it again. Re-run it after upgrading
`x8`, since the plist embeds the binary's resolved path.

## Generated plist

| Key | Value |
| --- | --- |
| `Label` | `com.x8.<profile-id>`, one agent per profile |
| `ProgramArguments` | `x8 serve --launchd --no-print-cache-settings`, plus `--workspace-directory` if given |
| `WorkingDirectory` | The directory `install` was run from |
| `Sockets.Listener` | `SockPathName` = ``XcodeServeRunner/defaultSocketPath(profileID:)``, mode `0600` |
| `StandardOutPath`, `StandardErrorPath` | `~/Library/Logs/X8/<label>.{out,err}.log` |
| `EnvironmentVariables` | `PATH`, plus any `--env` pairs |

`RunAtLoad`/`KeepAlive` are omitted on purpose: launchd holds the socket and
starts x8 on the first connection, and again after any exit. A `KeepAlive`
loop would only turn a bad `.x8.yml` into a throttled crash cycle.

## Managing the service

`x8 launchd status` prints `launchctl print` for the profile's service —
"Not installed" if it isn't bootstrapped. `x8 launchd uninstall` boots it
out and removes the plist.

For anything else, `launchctl` is the supervisor; use the
`gui/<uid>/com.x8.<profile-id>` service target directly (the `load`/`unload`
subcommands are legacy):

| Action | Command |
| --- | --- |
| Restart the process, keep the service and socket | `launchctl kickstart -k gui/$(id -u)/com.x8.<profile-id>` |
| Start now without waiting for a connection | `launchctl kickstart gui/$(id -u)/com.x8.<profile-id>` |
| Stop without removing the plist | `launchctl bootout gui/$(id -u)/com.x8.<profile-id>` |

`bootout` and `kickstart -k` send `SIGTERM`; x8 drains in-flight requests and
exits. launchd removes the socket node on `bootout` and keeps it across
`kickstart`. A `bootout` without `x8 launchd uninstall` leaves the plist in
place — `x8 launchd install` (or `launchctl bootstrap` on the existing
plist) starts it again.

## Pointing Xcode at the socket

Xcode needs the three cache settings, with the path equal to what
`x8 launchd install` printed, plus six prefix-mapping settings and an empty
module-validation session path (see <doc:PrefixMapping>):

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = /Users/USERNAME/Library/Application Support/X8/<profile-id>/cache.sock
SWIFT_ENABLE_PREFIX_MAPPING = YES
SWIFT_ENABLE_PROJECT_PREFIX_MAPPING = YES
CLANG_ENABLE_PREFIX_MAPPING = YES
CLANG_ENABLE_PROJECT_PREFIX_MAPPING = YES
CLANG_MODULES_BUILD_SESSION_FILE =
SWIFT_OTHER_PREFIX_MAPPINGS = $(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built $(OBJROOT)/../..=/^dd /path/to/workspace=/^workspace
CLANG_OTHER_PREFIX_MAPPINGS = $(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built $(OBJROOT)/../..=/^dd /path/to/workspace=/^workspace
```

Put them in an xcconfig applied to the project or targets, or pass them as
`xcodebuild` arguments for command-line builds. Scheme environment variables
are not read by the build system and do not work. These settings configure the
socket and key normalization only. X8 does not rewrite the caller's source or
DerivedData paths. It intentionally does not require a fixed workspace,
package, or DerivedData layout, because that would not be portable to another
checkout or machine.

Prefix mapping normalizes source, DerivedData, and product roots; it does
not make generated macro plugin executables identical between worktrees, so
macro-heavy targets can still miss across worktrees. See <doc:PrefixMapping>
for that limitation.

## Troubleshooting

`x8 launchd status` (or `launchctl print gui/$(id -u)/com.x8.<profile-id>`)
is the first stop. Read `state`, `pid`, `last exit code`, and the `Listener`
entry under `sockets`. Then read the service's `StandardErrorPath`
(`~/Library/Logs/X8/com.x8.<profile-id>.err.log`).

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `status`: "Not installed" | Not bootstrapped | `x8 launchd install` |
| `last exit code` non-zero right after a connection, stderr says config not found | `install` was run from a directory without `.x8.yml` | Re-run `x8 launchd install` from the right directory |
| Xcode: connection refused, socket file exists | Orphaned node from a foreground `x8 serve` that was killed with `SIGKILL` at the same path; launchd is not listening on it | Confirm with `status` that the loaded service's `Listener` path differs, `rm` the orphan, fix the build setting |
| Xcode: no such file | Service not installed, or the Xcode build setting doesn't match what `install` printed | `x8 launchd install`; compare the printed path against the build setting |
| Backend auth errors in stderr | Shell-profile environment not present under launchd | Re-run `install` with `--env KEY=VALUE`, or put credentials in `.x8.yml` |
| Builds succeed but never hit the cache, stderr clean | Prefix mapping off, or the target has path-sensitive inputs not covered by Xcode's mappings (<doc:PrefixMapping>) | Add all six prefix-mapping settings, then check the known limitations in <doc:PrefixMapping> |
| Builds succeed but never hit the cache, backend errors in stderr | Cache misses are fail-open | Fix backend, `launchctl kickstart -k gui/$(id -u)/com.x8.<profile-id>` |

Full reset:

```sh
x8 launchd uninstall
x8 launchd install
```

The socket node is normally gone after `uninstall`'s `bootout`; if it
remains, nothing owns it and removing it is safe. None of this touches the
S3 cache itself.
