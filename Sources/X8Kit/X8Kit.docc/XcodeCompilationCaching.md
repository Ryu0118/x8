# How Xcode reuses compilation results

Compiling a source file takes time. When compilation caching is enabled, Xcode
can reuse a result from an earlier build instead of compiling the same work
again. Xcode checks its local cache first; a remote cache lets other machines
reuse results too.

X8 connects Xcode to that shared cache. It stores compilation results in the
storage you configure, so a build on one machine can help a later build on
another.

## When can Xcode reuse a result?

Xcode reuses a result only when the compilation inputs match. Those inputs
include the source, compiler, build settings, and dependencies. If any of them
change, Xcode compiles again and may store the new result for later builds.

Build paths can differ between machines even when the project is otherwise the
same. X8's prefix mapping makes common paths consistent; see [Prefix mapping
and cache portability](https://ryu0118.github.io/x8/documentation/prefixmapping)
for its requirements and limits.

A cache miss is normal: Xcode compiles the work on the current machine. If the
remote cache cannot be reached, X8 lets the build continue by compiling
locally. The cache speeds up matching compilation work; it does not skip other
build steps such as linking or signing.

## Try it

For a command-line build, run:

```sh
x8 xcodebuild -workspace MyApp.xcworkspace -scheme MyApp build
```

For Xcode.app builds, start `x8 serve` and add its printed settings to your
app target or an `.xcconfig`. See [Use X8 with Xcode](https://ryu0118.github.io/x8/documentation/xcodecacheruntime)
for the steps.

The official `x8` executable uses S3-compatible storage. To use another
provider, build a custom executable with `X8CLI`; see the [custom storage
guide](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli).
