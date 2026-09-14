# Architecture and Testability

This rule covers runtime boundaries and how behavior is made reusable and
testable. Repository change procedure belongs in the change-management rule.

## Module boundaries

- `x8` is the S3-only composition root: connect X8Config loading and presentation, S3Storage construction, and cleanup to X8CLI.
- `X8CLI` owns the shared command tree, argument parsing, presentation, external-process adapter, and command-scoped storage ownership. It accepts separate configuration, storage, and shutdown closures without requiring a CLI-specific storage protocol.
- `X8Kit` owns cache-server use cases through focused session and server types. It is an internal implementation layer of `X8CLI`, not a directly embeddable public library; a custom executable builds on `X8CLI` instead.
- `X8Storage` owns the storage protocol and cache hit/miss semantics; `X8S3` owns the S3-compatible adapter.
- `X8Core` owns lowest-level domain types and must not depend on storage, networking, Soto, or CLI code.
- Keep dependencies one-directional:
  `x8 -> X8CLI -> X8Kit -> X8Storage -> X8Core` and, when the `S3` trait is enabled,
  `x8 -> X8S3 -> X8Storage -> X8Core`.
- `X8Kit` must remain backend-agnostic. It accepts storage protocols and never
  imports, constructs, or selects `X8S3` or another concrete backend.
- `X8CLI` must not depend on X8Config, YAML, Soto, or a concrete storage module. The official `.x8.yml` schema belongs to the S3 executable; independent executables own their schemas and credential resolution.
- Backend construction belongs in the executable's composition root or in a
  backend-specific factory owned by that composition root. A custom frontend
  may select a different backend without making `X8Kit` resolve its package.
- A configuration loader only locates, reads, and decodes configuration
  documents. Expansion, defaulting, validation, credential construction, and
  backend construction belong to separate layers.

## Runner boundary

- Use one focused Kit type per use case, such as `XcodeCacheSession` or `DoctorRunner`.
- A Kit use-case type owns cache orchestration, branching, policies, and error classification; it must not parse `argv`, call `exit`, launch external clients, or print directly. The frontend may translate an external client's result into an exit status.
- X8CLI contains the thin external-process adapter: argument passthrough, cache-setting injection, stream forwarding, and exit-status mapping. Kit owns socket lifecycle and cache use cases; provider code owns credentials and remote calls. Shared role wrappers gate Xcode traffic without changing diagnostics or administration.
- Other frontends must call the same Kit use-case type. A service/facade may route requests or encode results, but must not duplicate use-case logic.

## Testability

- Hide side effects behind focused protocols and provide live implementations as initializer defaults when practical.
- Test Runners with fakes, spies, and deterministic fixtures; unit tests must not require AWS/R2, network, credentials, real sockets, or `xcodebuild`.
- Use Swift Testing for unit tests. Put provider and end-to-end checks in explicitly named integration tests.
- Do not extract an abstraction from code that only looks similar; require shared behavior, guards, and result semantics.

The official executable and external consumers use the same X8CLI commands;
those commands validate input and construct Kit use-case types. Do not duplicate
command definitions or store configuration and storage in global mutable state.
