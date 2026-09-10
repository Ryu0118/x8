# Cache Model

How Action Cache keys, result metadata, and CAS identifiers relate.

## Overview

The Xcode compilation cache has two related but distinct parts: an Action
Cache that records the result of a compilation action, and CAS that stores the
result data.

## Compilation actions

An action is one build-system compilation job, such as a compiler invocation
with its source inputs, toolchain, arguments, and other relevant settings. The
action is not a user interaction or a project identifier.

`X8Core.ActionCacheKey` is the opaque binary key Xcode assigns to that action. It is
used only to look up the action's result record through ``ActionCacheStore``.
X8 must preserve it without trying to reconstruct its contents.

## Action Cache records

`X8Core.ActionCacheValue` is the `KeyValueDB` value for an action key. It is a map
from string entry names to opaque bytes. The observed `value` entry contains
serialized compilation-result metadata, which can refer to one or more
`X8Core.CASDataID` values. The value is metadata, not the compiled bytes themselves.

## CAS records

`X8Core.CASDataID` identifies one immutable CAS blob or complete object. A
``CASObject`` contains payload bytes and an ordered list of IDs for other CAS
records. Those references form the CAS object graph.

The relationship is therefore:

```text
ActionCacheKey
    -> ActionCacheValue result metadata
        -> CASDataID
            -> CAS blob or object graph
```

Xcode supplies the identifier bytes. X8 preserves them and maps them to a
provider-specific location only at the storage-adapter boundary.
