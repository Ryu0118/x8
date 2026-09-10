# Connecting your configuration

Keep the schema in your executable and expose only what the shared CLI needs.

## Own the schema

`configuration:` is an asynchronous throwing closure returning
``X8CLIConfiguration``. It can read your own YAML or JSON file, environment
variables, or fixed values. X8CLI does not search for `.x8.yml`, require a bucket
or region, or expand environment variables on your behalf.

The closure must finish local validation without starting remote authentication
or opening a client. Perform those operations in `storage:` instead.

The configuration wrapper carries:

| Value | Contract |
| --- | --- |
| `value` | Your validated, Sendable input, passed unchanged to the storage factory. |
| `profileID` | A stable, non-secret identity for one cache domain. |
| `role` | Read/write permissions for Xcode cache traffic; defaults to both. |
| `displayFields` | Ordered non-secret key/value pairs printed by `config show`. |
| `credentialSource` | Authentication mechanism description for diagnostics. |
| `storageDescription` | Non-secret description of the domain for administration. |

The CLI never reflects on `value`. Display fields are printed exactly in their
supplied order; include any common fields you want shown. Supply no secret keys,
tokens, signed URLs, or connection strings in display or diagnostic descriptions.

## Keep identity stable

Include the storage kind and the complete non-secret cache domain when deriving
`profileID`. Different domains must not share a runtime identity. Credential
rotation and a change between producer and consumer must not change that identity.

The identifier becomes a local directory component and must contain 1–64 ASCII
letters, digits, underscores, or hyphens. Configuration construction rejects
path separators, traversal components, whitespace, and other characters. A
short digest of a canonical domain representation is suitable; the example
prefixes its digest with `memory-`.

## Command behavior

Help, version, and completion generation do not invoke the loader. `config
validate` resolves and validates your configuration; `config show` additionally
prints the supplied display fields. Neither opens storage or verifies remote
credentials. Commands that use the cache resolve once and open storage afterward.

`role` controls Xcode cache reads and writes through shared storage wrappers.
It is not a cloud authorization mechanism. The read-only `doctor` probe and
explicit administrative commands retain their own behavior independently of
the traffic role; cloud permissions still govern those requests.
