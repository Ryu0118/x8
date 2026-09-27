# Configuring x8 with .x8.yml

Describe where the cache lives, how each machine reads and writes it, and
which credentials x8 may use.

## Overview

x8 reads `.x8.yml` from the directory it runs in, normally the project root.
It is the file every machine shares, so commit it. An optional, git-ignored
`.x8.local.yml` next to it overlays values for the machine it lives on; use it
only when a value is genuinely machine-specific rather than something every
clone of the repository should share.

Every key can appear in either file, every value supports POSIX-style
`$VAR`/`${VAR}` expansion against the process environment, and unknown keys at
any level are rejected with their key path, so a typo never silently falls
back to a default.

```yaml
version: 1
s3:
  api:                       # signed S3 API access; only when read or write is api
    endpoint: https://…      # optional
    region: us-east-1        # optional
    bucket: my-team-cache
    credentials:
      source: static         # static | defaultChain
      accessKeyID: ${AWS_ACCESS_KEY_ID}
      secretAccessKey: ${AWS_SECRET_ACCESS_KEY}
      sessionToken: ${AWS_SESSION_TOKEN}
  read: api                  # api | none | { publicURL: https://… }
  write: api                 # api | none
socketPath: ${HOME}/.x8/cache.sock   # optional
```

## Keys

| Key | Required | Description |
| --- | --- | --- |
| `version` | yes | Config schema version. Currently `1`. |
| `s3.read` | yes | How this machine reads the cache: `api` (signed `GetObject`), `publicURL` (unsigned GET, no credentials), or `none` (every read is a miss, no network). |
| `s3.write` | yes | How this machine writes the cache: `api` (signed `PutObject`) or `none` (writes are rejected). There is no public-URL write; anonymous writes would let anyone poison the cache. |
| `s3.read.publicURL` | with `publicURL` | Public object URL prefix ending in `/`. x8 reads `publicURL + cas/<id>` and `publicURL + action-cache/<key>`. Must be `https` (plain `http` only for `localhost`). |
| `s3.api` | when `read` or `write` is `api` | Signed API access shared by both paths. Configuring it while neither path uses it is an error. |
| `s3.api.bucket` | yes | The S3 bucket name. |
| `s3.api.region` | no | AWS region or provider-specific signing region. Defaults to `us-east-1`. |
| `s3.api.endpoint` | no | Custom endpoint for an S3-compatible provider such as R2 or MinIO. Omit for AWS S3. |
| `s3.api.credentials.source` | yes | `defaultChain` uses the standard AWS credential provider chain (environment, shared config file, SSO, `AssumeRole`, and container or instance metadata); `static` uses the keys below. |
| `s3.api.credentials.accessKeyID` / `secretAccessKey` | with `static` | Static key pair. Never commit a literal value; use `$VAR` expansion. |
| `s3.api.credentials.sessionToken` | no | Optional session token for temporary/STS credentials, with `static`. |
| `socketPath` | no | Fixed Unix socket path for the cache proxy, shared by `serve`, `serve stop`, `tail`, and `stats`. Must be an absolute path under 104 UTF-8 bytes. Omit to use the per-user default derived from the profile. |

`x8 config validate` checks both files and their resolved values, and
`x8 config show` prints the resolved, non-secret result.

## Reads, writes, and local overlays

Reads and writes are enforced at the storage boundary: `read: none` returns
cache misses without contacting storage, and `write: none` rejects writes
before reaching storage. Neither changes where the cache lives, so a CI runner
that writes and a laptop that reads share one cache. `read: api` with
`write: api` is often enough.

Use `.x8.local.yml` only when specific machines need a different path.
`s3.read`, `s3.write`, and `s3.api.credentials` are replaced whole by an
overlay, so switching a path or credential source never leaves fields from the
other choice behind. The other `s3.api` fields and `socketPath` are overridden
key by key.

## Reading without credentials

When the bucket's objects are publicly readable, readers need no credentials
at all: with `read: { publicURL: … }` and no `s3.api`, x8 never constructs an
S3 client or consults the credential chain. The writer keeps signed access:

```yaml
# .x8.yml, shared by every clone: developers read over the public URL
version: 1
s3:
  read:
    publicURL: https://cache.example.com/
  write: none
```

```yaml
# .x8.local.yml on a CI runner that populates the cache
s3:
  api:
    bucket: my-team-cache
    endpoint: https://abc123.r2.cloudflarestorage.com
    credentials:
      source: static
      accessKeyID: ${AWS_ACCESS_KEY_ID}
      secretAccessKey: ${AWS_SECRET_ACCESS_KEY}
  write: api
```

Example public URLs are an R2 bucket's `r2.dev` or custom domain
(`https://cache.example.com/`), a path-style MinIO bucket
(`https://minio.example.com/my-team-cache/`), or an AWS S3 bucket
(`https://my-team-cache.s3.us-east-1.amazonaws.com/`). Grant anonymous
`s3:GetObject` only; never grant anonymous writes. x8 does not follow
redirects on the public URL, so use its final form.

A missing object usually answers `404`, which x8 treats as a cache miss; MinIO
and R2 public buckets do so. AWS S3 answers `403 AccessDenied` instead when
anonymous `s3:ListBucket` is not granted, which looks the same as a real
permission error. To tell them apart, a writer (`write: api`) publishes a small
probe object, `cas/_x8-probe` and `action-cache/_x8-probe`, after its first
write to each namespace. After a `403 AccessDenied`, a public reader fetches
the probe: if the probe loads, the `403` is a miss; otherwise the read fails as
a permission error. Run a writer once before relying on this, and don't put a
CDN rule in front that rewrites `403` to `404`. `x8 cache purge` never lists or
deletes the probes. Purge and other administration need `s3.api`.

## Pinning the socket path

`socketPath` is where `$VAR` expansion earns its keep: commit one path with a
per-user variable and the resolved path stays fixed for each user:

```yaml
socketPath: ${HOME}/.x8/cache.sock
```

`x8 serve --socket-path` overrides it for one invocation, and its detached
child inherits the override; `x8 serve stop` and `x8 tail` accept the same
option to address a server started that way. `x8 xcodebuild` has no
`--socket-path` option. It always uses its own invocation-scoped temporary
cache socket, so multiple invocations and a concurrent `x8 serve` on the same
profile keep working side by side. `socketPath` still applies to its
live-events socket, so `x8 tail` can observe an `x8 xcodebuild` build's
traffic at the pinned location.
