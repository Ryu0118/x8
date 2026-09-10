# Change Management and Validation

This rule covers repository changes, commit hygiene, and validation. Runtime
design and source documentation belong in the other two rules.

## Commits and communication

- Keep each commit focused on one concern and write commit messages in English.
- Write pull-request titles/bodies, issue comments, and review comments in English.
- For a pure directory or file move, use `git mv` in a behavior-neutral commit before editing contents.
- Follow `implementation -> commit -> deploy`; this repository currently has no deployment target, so do not invent one.
- Never add `Codex-Session:` URLs to commits or pull requests.

## Validation and safety

- After every content-changing commit, run the narrowest relevant validation. For source changes use `swift build`, `swift build --traits S3`, `swift test`, `swift test --traits S3`, `mise exec -- swiftformat Sources Tests Package.swift --lint`, and `mise exec -- my-swift-linter lint` when those targets exist.
- If `docsync.yml` tracks a changed or moved file, run `docsync check` and update its checksum before committing.
- Use `rg`, `rg --files`, and scoped `ls`; never use a broad `find` over a home directory or workspace parent.
- Do not modify unrelated user changes or remove artifacts unless their ownership and generated nature are clear.
- Do not perform destructive Git operations (`checkout`, `reset --hard`, `clean -f`, or broad deletion) without explicit user approval.

When the repository is intentionally a skeleton, validate the package
manifest/target graph and report that build or test execution is unavailable
until source files exist.

## Investigation decisions

When measurements stop improving, do not continue cycling through changes.
Separate observed facts, concrete constraints, and unknowns; state the next
falsifiable hypothesis, its expected effect, and the check that will decide it
before running another experiment. If the target cannot be reached within the
allowed changes, say so explicitly with evidence and the conditions needed to
reach it. Do not present partial improvement as completion. Distinguish stock
toolchain results from results requiring an experimental service or build
setting tradeoff. Keep reported measurements current.
