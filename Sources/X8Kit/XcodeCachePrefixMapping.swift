/// Whether X8's cache-settings contract asks Xcode to prefix-map absolute
/// paths out of compilation-cache keys.
///
/// `enabled` adds four prefix-mapping enable flags and the two
/// `SWIFT_OTHER_PREFIX_MAPPINGS`/`CLANG_OTHER_PREFIX_MAPPINGS` values so keys
/// can normalize supported source and output paths. It also clears
/// `CLANG_MODULES_BUILD_SESSION_FILE`: Swift hashes that optimization-only
/// path without scanner remapping. Normal module validation remains. Without them a
/// shared cache misses on every machine whose paths differ, so `enabled` is
/// the default for every X8 client. `disabled` exists for a project that sets
/// these settings itself and must not have them overridden by X8.
public enum XcodeCachePrefixMapping: Sendable, Equatable {
    case enabled
    case disabled
}
