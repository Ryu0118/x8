import Foundation

/// Builds the environment contract shared by X8's Xcode clients.
///
/// Every client-facing mode enables compilation caching and the cache plugin,
/// points `COMPILATION_CACHE_REMOTE_SERVICE_PATH` at the selected Unix
/// socket, and by default turns on Xcode's partial prefix mapping. This does
/// not eliminate every path-sensitive compiler input. Keeping it in one place
/// prevents standalone diagnostics and child-process injection from drifting
/// apart.
package enum XcodeCacheEnvironment {
    /// A working directory cannot be represented in the space-separated
    /// `*_OTHER_PREFIX_MAPPINGS` value format Xcode expects.
    package enum WorkingDirectoryError: Error, Equatable, Sendable, CustomStringConvertible {
        /// The path contains a space, which the mapping format has no way to
        /// escape or quote; embedding it would silently corrupt every
        /// mapping in the same value.
        case containsSpace(path: String)

        /// A message identifying the offending path and how to resolve it.
        package var description: String {
            switch self {
            case let .containsSpace(path):
                "Workspace directory '\(path)' contains a space, which "
                    + "SWIFT_OTHER_PREFIX_MAPPINGS/CLANG_OTHER_PREFIX_MAPPINGS cannot represent "
                    + "(the format has no quoting or escaping). Move the checkout to a path "
                    + "without spaces, or pass --no-prefix-mapping."
            }
        }
    }

    private static let cachingKey = "COMPILATION_CACHE_ENABLE_CACHING"
    private static let pluginKey = "COMPILATION_CACHE_ENABLE_PLUGIN"
    private static let remoteServicePathKey = "COMPILATION_CACHE_REMOTE_SERVICE_PATH"

    /// Apple's build specs give these no default, so they are off unless set.
    ///
    /// `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`/`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`
    /// are enabled for Xcode 27+, where the bundled specs map project source,
    /// DerivedData, and product roots. Xcode 26.5 did not attach rules to
    /// those names. `SWIFT_OTHER_PREFIX_MAPPINGS`/`CLANG_OTHER_PREFIX_MAPPINGS`
    /// still cover common DerivedData roots on toolchains that consume them.
    private static let prefixMappingKeys = [
        "SWIFT_ENABLE_PREFIX_MAPPING",
        "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING",
        "CLANG_ENABLE_PREFIX_MAPPING",
        "CLANG_ENABLE_PROJECT_PREFIX_MAPPING",
    ]

    private static let otherPrefixMappingsKeys = [
        "SWIFT_OTHER_PREFIX_MAPPINGS",
        "CLANG_OTHER_PREFIX_MAPPINGS",
    ]

    private static let logicalWorkspacePrefix = "/^workspace"
    private static let derivedPrefixMappings =
        "$(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built $(OBJROOT)/../..=/^dd"

    /// Maps common roots in Xcode's default DerivedData layout.
    ///
    /// A custom OBJROOT changes what its grandparent covers. Package project
    /// roots can differ from the workspace used as the compiler's working
    /// directory, so both need logical mappings. See the PrefixMapping article
    /// for the remaining compiler-key and output-replay limitations.
    private static let otherPrefixMappingsValue =
        "\(derivedPrefixMappings) $(WORKSPACE_DIR)=\(logicalWorkspacePrefix)"

    /// Validates that `workingDirectory` can be represented in the
    /// prefix-mapping value format, without building the full environment.
    ///
    /// Callers that create server-side resources before computing
    /// `cacheEnvironment` (so a validation failure need not unwind that
    /// state) call this first.
    package static func validate(workingDirectory: URL?) throws {
        _ = try prefixMappings(workingDirectory: workingDirectory)
    }

    /// Builds the Xcode cache-setting environment for one endpoint.
    ///
    /// - Throws: If `workingDirectory` cannot be represented in the
    ///   prefix-mapping value format.
    package static func values(
        socketPath: String,
        prefixMapping: XcodeCachePrefixMapping,
        workingDirectory: URL? = nil
    ) throws -> [String: String] {
        var values = [
            cachingKey: "YES",
            pluginKey: "YES",
            remoteServicePathKey: socketPath,
        ]

        guard prefixMapping == .enabled else { return values }
        // Swift 6.4 hashes this physical path without applying scanner maps.
        // Omit the once-per-session optimization; normal module validation remains.
        values["CLANG_MODULES_BUILD_SESSION_FILE"] = ""
        for key in prefixMappingKeys {
            values[key] = "YES"
        }
        let mapping = try prefixMappings(workingDirectory: workingDirectory)
        for key in otherPrefixMappingsKeys {
            values[key] = mapping
        }
        return values
    }

    private static func prefixMappings(workingDirectory: URL?) throws -> String {
        guard let workingDirectory else { return otherPrefixMappingsValue }

        let normalizedWorkingDirectory = workingDirectory.standardizedFileURL.path
        // The mapping value is space-separated with no quoting or escaping,
        // so a path containing a space would silently split into unrelated
        // fragments instead of one mapping entry.
        guard !normalizedWorkingDirectory.contains(" ") else {
            throw WorkingDirectoryError.containsSpace(path: normalizedWorkingDirectory)
        }
        return "\(derivedPrefixMappings) \(normalizedWorkingDirectory)=\(logicalWorkspacePrefix)"
    }
}
