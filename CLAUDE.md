# X8

Swift package for `x8`, an S3-compatible remote compilation cache proxy for
Xcode. It serves Xcode's compilation-cache gRPC protocol over a Unix-domain
socket and stores CAS objects and Action Cache values in an S3-compatible
bucket. The package is split into a domain layer (`X8Core`), a storage
boundary (`X8Storage`), the S3 adapter (`X8S3`), reusable cache use cases
(`X8Kit`), YAML configuration (`X8Config`), the shared command tree (`X8CLI`),
and the official executable (`x8`).

## Commands

| Command | Purpose |
| --- | --- |
| `swift package dump-package` | Validate `Package.swift` and inspect the target graph. |
| `swift build` | Build the package targets that contain Swift sources. |
| `swift test` | Run the package tests. |
| `swift run x8` | Run the CLI. |
| `mise exec -- my-swift-linter lint` | Run the configured Swift AST lint rules. |

## Architecture

```text
Sources/x8/         S3-only executable and configuration/storage composition
Sources/X8CLI/      shared command interface with injected configuration and storage
Sources/X8Kit/      storage-agnostic cache use cases for custom interfaces
Sources/X8Config/   YAML configuration loading/resolution and S3-shaped profile model
Sources/X8S3/       S3-compatible storage adapter
Sources/X8Storage/  storage protocol and cache semantics
Sources/X8Core/     lowest-level domain types
```

See the Architecture and Testability rule for dependency direction and the
boundary between frontend, Kit, storage, and domain code.

`AGENTS.md` is a symlink to this file. Update `CLAUDE.md`, never the symlink.

## Detailed coding rules

These rules apply repository-wide and are intentionally partitioned by concern:

- [Architecture and testability](.agents/rules/architecture-and-testability.md) — module boundaries, Runner ownership, dependency injection, and tests.
- [Swift and documentation](.agents/rules/swift-and-documentation.md) — Swift access/concurrency, source organization, comments, and DocC.
- [Change management and validation](.agents/rules/change-management-and-validation.md) — commits, repository communication, validation, and Git safety.

## Project constraints

- Keep cache misses distinct from remote errors so fail-open behavior remains possible.
- Treat Xcode CAS object identifiers as opaque; do not replace them with a new hash or an S3 ETag.
- Keep streaming and cancellation at the storage boundary; do not buffer whole objects by default. Bounded metadata/codecs and the intentionally in-memory test double are explicit exceptions.
- `X8S3` is the only production storage adapter for now and may support AWS S3 and S3-compatible endpoints.
- The official `x8` remains S3-only. Other storage implementations use `X8CLI` in an independent executable with their own configuration schema.
- Keep shared CLI Swift sources directly under `Sources/X8CLI`; do not add an `API` directory or override its target path.
- Keep `stats` an undocumented diagnostic: preserve direct invocation without advertising it in help, README, or new user guides.
- Keep Soto and S3-specific configuration out of `X8Core` and `X8Storage`.
- Verify the Xcode compilation-cache wire protocol before designing protocol-specific APIs.
- Keep generated gRPC sources under `Sources/X8Kit/Generated`; use the Kit proxy as the reusable public surface.
