# Use X8 with Xcode

X8 connects Xcode to a shared compilation cache. Choose how to run it based on
how you start your builds.

## Build from Terminal

Run `xcodebuild` through `x8`:

```sh
x8 xcodebuild -workspace MyApp.xcworkspace -scheme MyApp build
```

X8 starts the cache service for that build, configures Xcode to use it, and
stops the service when the build ends. You do not need to start `x8 serve` or
change your project settings.

## Build from Xcode.app

Xcode.app needs a cache service that stays running while you build. From your
project directory, start it with:

```sh
x8 serve
```

X8 prints settings for Xcode. Add those settings to your app target or an
`.xcconfig`, then leave `x8 serve` running while you build. To run it in the
background, use `x8 serve -d`; stop it later with `x8 serve stop`.

## Share the same cache

Machines share results when they use the same cache configuration. The local
connection used by Xcode only tells it where to reach X8; it does not choose
the cache itself.

The official `x8` executable uses S3-compatible storage. To use another
storage provider, build a separate executable with `X8CLI`; see the [custom
storage guide](https://ryu0118.github.io/x8/documentation/x8cli/creatingacustomcli).
For storage and credential settings, see [Configuring x8 with
.x8.yml](https://ryu0118.github.io/x8/documentation/configurationfile).
