# ``X8CLI``

The shared x8 command interface for executables with independently chosen storage.

## Overview

The official `x8` executable supports S3-compatible storage only. To use another
storage implementation with the same command interface, build your own executable
with ``X8CLI``. Supply a configuration loader, a storage factory, and asynchronous
cleanup when required. You do not implement another command tree or a CLI-specific
storage protocol.

`X8CLI` owns argument parsing, command output, and the external `xcodebuild`
process adapter. `X8Kit` owns the cache-server use cases. `X8Storage` defines
the CAS, Action Cache, and optional administration contracts.

The shared CLI does not import X8Config or S3. Your executable chooses its own
configuration files, schema, environment variables, and authentication. The
official `.x8.yml` schema remains specific to the S3-only `x8` executable.

## Topics

### Building an executable

- <doc:CreatingACustomCLI>
- <doc:ConnectingConfiguration>
- <doc:StorageLifetime>

### Entry points

- ``X8CLI``
- ``X8CLIConfiguration``
