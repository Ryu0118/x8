# Configuration flow

## Overview

X8 configuration is resolved in three deliberately separate stages:

1. ``X8ConfigurationLoader`` locates `.x8.yml`, reads the raw YAML layers through
   its injected `FileManagerProtocol`, and applies the optional `.x8.local.yml`
   override.
2. ``X8ConfigurationResolver`` expands supported scalar parameters, applies
   defaults, validates values, and produces ``X8Configuration``.
3. The official executable constructs S3 storage from the resolved value.
   X8CLI and X8Kit receive that storage without selecting a provider or
   interpreting the S3 configuration schema.

The loader checks only the caller's selected directory. Its default public
overload uses the process current working directory; it does not inspect
forwarded `xcodebuild` arguments or walk parent directories.
Loading is exposed as `async throws` so filesystem-backed configuration stays
on the same asynchronous boundary as the rest of the application.

The loader does not execute YAML as a shell script, and the resolver keeps
assignment-style parameter expansion inside its own in-memory environment.
