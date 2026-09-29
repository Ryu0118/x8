# ``X8Config``

YAML-based configuration loading, resolution, and presentation for the official
S3-only x8 executable.

## Overview

``X8ConfigurationLoader`` locates and decodes `.x8.yml` (and an optional
`.x8.local.yml` override) into a raw ``X8ConfigurationDocument``.
``X8ConfigurationResolver`` then expands scalar parameters, applies defaults,
and validates the result into an ``X8Configuration`` containing S3-shaped
profile fields and optional ``RemoteCacheCredentials``. The executable uses
that value to construct S3 storage. `X8Config` performs no network or storage
I/O and never selects a storage implementation itself.

Independent executables using X8CLI define their own configuration formats and
do not need this module. The `.x8.yml` schema is not a shared configuration
schema for other storage providers.

## Topics

- <doc:ConfigurationFile>
- ``X8ConfigurationLoader``
- ``X8ConfigurationResolver``
- ``X8Configuration``
- ``X8ConfigurationDocument``
- ``RemoteCacheCredentials``
