# ``X8Core``

Foundational value types shared by the X8 storage layers.

## Overview

`X8Core` models identifiers and cache values without knowing how they are
transported or persisted. CAS identifiers and Action Cache keys are opaque
bytes: callers must preserve them exactly and must not replace them with a
project name, an S3 key, or a newly computed identifier.

`ActionCacheValue` preserves the string-to-bytes entries returned by Xcode.
Parsing protocol messages and deciding how those values are stored belongs to
higher layers.
