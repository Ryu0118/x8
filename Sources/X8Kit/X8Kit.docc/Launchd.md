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

The LaunchAgent's `WorkingDirectory` must contain `.x8.yml` because
`X8ConfigurationLoader` intentionally checks only the current directory.

## There is no `x8 stop`

launchd owns start, stop, and restart for this mode. x8 never binds or
removes the socket node, so it can't tear the service down either: killing
the x8 process just gets it relaunched on the next connection, since
launchd still holds the socket. Use `launchctl` (below) for start, stop,
restart, and status.

## LaunchAgent template

Copy the template below to `~/Library/LaunchAgents/<Label>.plist` and replace:

| Field | Replace with |
| --- | --- |
| `Label` and filename | A reverse-DNS name, one per `.x8.yml` |
| `ProgramArguments[0]` | Absolute path to `x8` (`which x8`) |
| `WorkingDirectory` | Absolute path to the directory holding `.x8.yml` |
| `SockPathName` | Absolute socket path; `~` is not expanded |
| `StandardOutPath`, `StandardErrorPath` | Absolute log paths |
| `EnvironmentVariables` | Anything the S3 backend needs (for example `AWS_PROFILE`); launchd does not source your shell profile |

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Reverse-DNS label. Must match the filename (<Label>.plist). One agent per .x8.yml. -->
    <key>Label</key>
    <string>com.example.x8.myproject</string>

    <!-- Absolute path to the x8 binary. `which x8` in a terminal; launchd has no shell PATH. -->
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/x8</string>
        <string>serve</string>
        <string>--launchd</string>
    </array>

    <!-- Directory containing .x8.yml. x8 reads the config from the CWD only. -->
    <key>WorkingDirectory</key>
    <string>/Users/USERNAME/src/myproject</string>

    <!-- The key MUST be "Listener": x8 adopts the socket via launch_activate_socket("Listener"). -->
    <key>Sockets</key>
    <dict>
        <key>Listener</key>
        <dict>
            <key>SockFamily</key>
            <string>Unix</string>
            <key>SockType</key>
            <string>stream</string>
            <!-- Stable path Xcode is pointed at. Parent directory must exist before bootstrap. -->
            <key>SockPathName</key>
            <string>/Users/USERNAME/Library/Application Support/X8/launchd/myproject.sock</string>
            <!-- 0600: only this user can connect. -->
            <key>SockPathMode</key>
            <integer>384</integer>
        </dict>
    </dict>

    <!-- On-demand: launchd holds the socket and starts x8 on the first connection.
         No RunAtLoad / KeepAlive: a broken config surfaces at build time instead of crash-looping. -->

    <!-- Builds are interactive work; keep x8 out of the background QoS tier. -->
    <key>ProcessType</key>
    <string>Interactive</string>

    <!-- Parent directory must exist before bootstrap. -->
    <key>StandardOutPath</key>
    <string>/Users/USERNAME/Library/Logs/X8/com.example.x8.myproject.out.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/USERNAME/Library/Logs/X8/com.example.x8.myproject.err.log</string>

    <!-- launchd does not source your shell profile. Set anything the S3 backend needs here,
         e.g. AWS_PROFILE. Not needed when credentials are in .x8.yml. -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin</string>
        <!--
        <key>AWS_PROFILE</key>
        <string>default</string>
        -->
    </dict>
</dict>
</plist>
```

The template omits `RunAtLoad` and `KeepAlive` on purpose. launchd holds the
socket and starts x8 on the first connection, and again after any exit. A
`KeepAlive` loop only turns a bad `.x8.yml` into a throttled crash cycle. Add
`RunAtLoad: true` if you want the backend connection warmed at login.

## Install

```sh
LABEL=com.example.x8.myproject
mkdir -p ~/Library/LaunchAgents \
         "$HOME/Library/Application Support/X8/launchd" \
         ~/Library/Logs/X8
# save the template above as ~/Library/LaunchAgents/$LABEL.plist, then edit its placeholders
plutil -lint ~/Library/LaunchAgents/$LABEL.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$LABEL.plist
launchctl print gui/$(id -u)/$LABEL | grep -E 'state|pid|last exit'
```

launchd creates the socket node at bootstrap; the parent directories must
already exist. The service shows `state = not running` until the first
connection.

If `bootstrap` reports the service is disabled (left over from an earlier
`launchctl disable`), run `launchctl enable gui/$(id -u)/$LABEL` first.

## Lifecycle

`launchctl` is the only supervisor. Use the `gui/<uid>/<Label>` service
target; the `load`/`unload` subcommands are legacy.

| Action | Command |
| --- | --- |
| Status: state, PID, last exit code, socket | `launchctl print gui/$(id -u)/$LABEL` |
| Stop and unload (removes the socket node) | `launchctl bootout gui/$(id -u)/$LABEL` |
| Restart the process, keep the service and socket | `launchctl kickstart -k gui/$(id -u)/$LABEL` |
| Start now without waiting for a connection | `launchctl kickstart gui/$(id -u)/$LABEL` |
| Apply an edited plist | `bootout`, then `bootstrap` again |

`bootout` and `kickstart -k` send `SIGTERM`; x8 drains in-flight requests and
exits. launchd removes the socket node on `bootout` and keeps it across
`kickstart`. Editing the plist in place has no effect on a loaded service.

## Pointing Xcode at the socket

Xcode needs the three cache settings, with the path equal to `SockPathName`,
plus six prefix-mapping settings and an empty module-validation session path
(see <doc:PrefixMapping>):

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = /Users/USERNAME/Library/Application Support/X8/launchd/myproject.sock
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
socket and key normalization only. Unlike `x8 xcodebuild`, a long-lived
`x8 serve --workspace-directory /path/to/workspace` selects the physical
directory used by the Xcode client; if omitted, the server maps the directory
from which it was launched. X8 does not rewrite the caller's source or
DerivedData paths. It intentionally does not require a fixed workspace,
package, or DerivedData layout, because that would not be portable to another
checkout or machine.

On Xcode 27+, the project prefix settings normalize the ordinary source,
DerivedData, and product roots. They do not make generated macro plugin
executables identical between worktrees, so macro-heavy targets can still miss
the cache across worktrees for that reason. See <doc:PrefixMapping> for this
limitation; a long-lived `serve` process must not be described as solving
that toolchain limitation.

`x8 serve --print-cache-settings` prints the same ten lines for whichever
socket the running instance serves; it is a convenience for foreground use,
not a substitute for setting the same socket path in Xcode.

## Troubleshooting

`launchctl print gui/$(id -u)/$LABEL` is the first stop. Read `state`, `pid`,
`last exit code`, and the `Listener` entry under `sockets`. Then read
`StandardErrorPath`.

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `print`: service not found | Not bootstrapped, or wrong label | `bootstrap` |
| `last exit code` non-zero right after a connection, stderr says config not found | `WorkingDirectory` does not contain `.x8.yml` | Fix path, `bootout`, `bootstrap` |
| Exits immediately with a socket-activation error | `Sockets` key is not `Listener`, or the plist was launched without `--launchd` | Fix plist, `bootout`, `bootstrap` |
| Xcode: connection refused, socket file exists | Orphaned node from an old `SockPathName` or from a foreground `x8 serve` that was killed with `SIGKILL`; launchd is not listening on it | Confirm with `print` that the loaded service's `Listener` path differs, `rm` the orphan, fix the build setting |
| Xcode: no such file | Service not loaded (`bootout` removed the node) or path mismatch between plist and xcconfig | `bootstrap`; diff the two paths |
| Backend auth errors in stderr | Shell-profile environment not present under launchd | Add to `EnvironmentVariables` or `.x8.yml` |
| Builds succeed but never hit the cache, stderr clean | Prefix mapping off, or the target has path-sensitive inputs not covered by Xcode's mappings (<doc:PrefixMapping>) | Add all six prefix-mapping settings, then check for known limitations in <doc:PrefixMapping>; a fixed build layout is not an X8 requirement or a macro-plugin fix |
| Builds succeed but never hit the cache, backend errors in stderr | Cache misses are fail-open | Fix backend, `kickstart -k` |

Full reset:

```sh
launchctl bootout gui/$(id -u)/$LABEL
rm ~/Library/LaunchAgents/$LABEL.plist
rm -f "$HOME/Library/Application Support/X8/launchd/myproject.sock"   # only if still present
# edit and reinstall
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$LABEL.plist
```

The socket node is normally gone after `bootout`; if it remains, nothing owns
it and removing it is safe. None of this touches the S3 cache itself.
