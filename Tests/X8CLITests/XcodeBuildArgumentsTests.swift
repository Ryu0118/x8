import Foundation
import Testing
@testable import X8CLI

@Suite("Xcode build path preservation")
struct XcodeBuildArgumentsTests {
    @Test(arguments: [
        ["build"],
        ["-derivedDataPath", "../My Build", "build"],
        ["-clonedSourcePackagesDirPath", "/external/packages", "build"],
        ["-workspace", "/worktrees/App.xcworkspace", "OBJROOT=/custom/objects", "build"],
    ])
    func preservesCallerArguments(arguments: [String]) {
        let build = XcodeBuildArguments(values: arguments)
        #expect(build.appending(cacheSettings: [:]) == arguments)
    }

    @Test
    func addsOnlyTheSuppliedCacheSettings() {
        let build = XcodeBuildArguments(values: ["build"])
        #expect(build.appending(cacheSettings: [
            "COMPILATION_CACHE_ENABLE_CACHING": "YES",
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH": "/tmp/cache.sock",
        ]) == [
            "build",
            "COMPILATION_CACHE_ENABLE_CACHING=YES",
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH=/tmp/cache.sock",
        ])
    }

    @Test
    func stagesResponsesAtTheCallerSelectedDerivedData() {
        let build = XcodeBuildArguments(values: ["-derivedDataPath", "/external/My Build"])
        #expect(build.responseDirectory?.path == "/external/My Build")
    }

    @Test(arguments: [["build"], ["build", "-derivedDataPath"]])
    func doesNotInventADerivedDataDirectory(arguments: [String]) {
        #expect(XcodeBuildArguments(values: arguments).responseDirectory == nil)
    }
}
