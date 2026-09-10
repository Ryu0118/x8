import Foundation
import Testing
@testable import X8Kit

@Suite("Xcode cache environment contract")
struct XcodeCacheEnvironmentTests {
    @Test
    func enabledPrefixMappingEmitsPortableCacheSettings() throws {
        let values = try XcodeCacheEnvironment.values(
            socketPath: "/tmp/x8/cache.sock",
            prefixMapping: .enabled
        )
        let otherMappings = "$(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built $(OBJROOT)/../..=/^dd $(WORKSPACE_DIR)=/^workspace"

        #expect(values == [
            "COMPILATION_CACHE_ENABLE_CACHING": "YES",
            "COMPILATION_CACHE_ENABLE_PLUGIN": "YES",
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH": "/tmp/x8/cache.sock",
            "SWIFT_ENABLE_PREFIX_MAPPING": "YES",
            "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
            "CLANG_ENABLE_PREFIX_MAPPING": "YES",
            "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
            "SWIFT_OTHER_PREFIX_MAPPINGS": otherMappings,
            "CLANG_OTHER_PREFIX_MAPPINGS": otherMappings,
            "CLANG_MODULES_BUILD_SESSION_FILE": "",
        ])
    }

    @Test
    func disabledPrefixMappingEmitsOnlyCacheSettings() throws {
        let values = try XcodeCacheEnvironment.values(
            socketPath: "/tmp/x8/cache.sock",
            prefixMapping: .disabled
        )

        #expect(values == [
            "COMPILATION_CACHE_ENABLE_CACHING": "YES",
            "COMPILATION_CACHE_ENABLE_PLUGIN": "YES",
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH": "/tmp/x8/cache.sock",
        ])
        #expect(values.keys.allSatisfy { !$0.hasSuffix("PREFIX_MAPPING") })
    }

    @Test
    func enabledPrefixMappingMapsTheClientWorkingDirectory() throws {
        let values = try XcodeCacheEnvironment.values(
            socketPath: "/tmp/x8/cache.sock",
            prefixMapping: .enabled,
            workingDirectory: URL(filePath: "/worktrees/MyApp")
        )
        let mappings = "$(PROJECT_TEMP_DIR)=/^derived $(BUILT_PRODUCTS_DIR)=/^built "
            + "$(OBJROOT)/../..=/^dd /worktrees/MyApp=/^workspace"

        #expect(values["SWIFT_OTHER_PREFIX_MAPPINGS"] == mappings)
        #expect(values["CLANG_OTHER_PREFIX_MAPPINGS"] == mappings)
    }

    @Test
    func workingDirectoryContainingASpaceIsRejected() {
        #expect(throws: XcodeCacheEnvironment.WorkingDirectoryError.self) {
            try XcodeCacheEnvironment.values(
                socketPath: "/tmp/x8/cache.sock",
                prefixMapping: .enabled,
                workingDirectory: URL(filePath: "/Users/dev/My Project")
            )
        }
    }

    @Test
    func validateRejectsAWorkingDirectoryContainingASpace() {
        #expect(throws: XcodeCacheEnvironment.WorkingDirectoryError.self) {
            try XcodeCacheEnvironment.validate(
                workingDirectory: URL(filePath: "/Users/dev/My Project")
            )
        }
    }

    @Test
    func validateAcceptsANilOrSpaceFreeWorkingDirectory() throws {
        try XcodeCacheEnvironment.validate(workingDirectory: nil)
        try XcodeCacheEnvironment.validate(workingDirectory: URL(filePath: "/worktrees/MyApp"))
    }
}
