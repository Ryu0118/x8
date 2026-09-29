# ``X8CLI``

The command interface for executables with independently chosen configuration and storage.

## Overview

The official `x8` executable supports S3-compatible storage only. To use another
backend, build a separate executable with ``X8CLI``. Supply your configuration,
storage implementation, and asynchronous cleanup when required. You do not
implement another command tree or a CLI-specific storage protocol.

`X8CLI` owns argument parsing, command output, and the external `xcodebuild`
process adapter. ``X8Storage`` defines the CAS, Action Cache, and optional
administration contracts.

The shared CLI does not import X8Config or S3. Your executable chooses its own
configuration files, schema, environment variables, and authentication. The
official `.x8.yml` schema remains specific to the S3-only `x8` executable.

## Topics

### Custom storage

- <doc:CreatingACustomCLI>

### Entry points

- ``X8CLI``
- ``X8CLIConfiguration``
