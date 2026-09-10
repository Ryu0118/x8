# Swift and Documentation

This rule covers source organization, API boundaries, and engineering prose.
Architecture and repository-change procedure are defined in separate rules.

## Swift boundaries

- Use Swift 6 strict concurrency and mark values crossing async boundaries `Sendable` where appropriate.
- Use `private` by default, `package` for implementation APIs shared inside this package, and `public` only for deliberate library APIs such as the `X8Kit` custom-CLI surface.
- Keep stored protocol dependencies as `any Protocol`; use `some Protocol` for initializer parameters when the concrete type need not escape.
- Keep one concern per file and group related files only when the group is meaningful; do not create a directory for a lone file.
- Within a function, separate setup, transformation, side effects, and result handling into readable blocks with blank lines. Do not insert blank lines between every statement.
- Keep lower-level modules independent of higher-level modules and implementation frameworks.
- Treat SwiftFormat, SwiftLint, and my-swift-linter configuration as the source of truth; do not silence warnings without a project-specific reason.
- Keep every rule exposed by the pinned my-swift-linter release explicitly configured in `.swift-ast-lint.yml` at error severity where supported. Keep `single-large-type-per-file` at 30 lines for top-level `public` and `package` types, and keep `missing-docs` at the `package` boundary without ignore patterns.

## Type selection and shared context

- Use an `enum` as a namespace only when its operations are stateless, pure
  helpers or process-wide format constants. Do not use an enum to hide a
  reusable configuration, dependency, resource, or invariant.
- Use a `struct` when several operations share immutable configuration or a
  dependency. Capture that context once, and precompute non-trivial derived
  values when doing so prevents repeated work or prevents callers from mixing
  values from different domains. Prefer this for keyspaces, wire adapters,
  filesystem boundaries, and similar per-operation contexts.
- Use an `actor` only when mutable state is shared across concurrent tasks and
  its mutations must be serialized. A shared instance alone is not a reason to
  use an actor; pure helpers and immutable context remain synchronous structs.
- Keep finite outcomes, modes, scopes, and error classifications as enums.
  Keep per-call parser or algorithm state local to a struct or function rather
  than turning a stateless helper into an actor.
- When reviewing an existing namespace, inspect all call sites for repeated
  configuration/dependency arguments, repeated derived-value construction,
  and cross-call invariants before deciding its type. Make the smallest
  context object that expresses those invariants; do not create a catch-all
  service or split a pure helper without a concrete shared context.

## Comments and documentation

Comments are optional. Before adding one, ask whether a future agent could
misread the intent or make the wrong change from the code alone. If not, do
not add it.

- Use `//` for a local, non-obvious reason or invariant.
- Use `///` for a non-obvious public/package API contract: behavior, inputs, outputs, errors, isolation, or lifetime.
- Use DocC for concepts spanning multiple symbols, modules, or workflow steps, such as cache protocol flow or storage layering.
- Keep a module overview in `<Module>.docc/<Module>.md`; add topic articles only when a symbol comment is insufficient.
- Explain why, external contracts, invariants, compatibility, failure, fallback, cancellation, or ownership. Do not narrate obvious code or comment every function.
- Treat `try?`, `@unchecked Sendable`, provider-listing filters, fallback branches, and cleanup races as review hotspots: add a concise rationale when the safety or ownership decision is not obvious from the code.
- Update or remove explanations when the behavior changes or becomes self-evident.

Follow `../egg`'s concise module overview plus topic-article pattern. All
source comments, documentation comments, DocC, identifiers, test names, and
diagnostic messages written in the repository are English.
