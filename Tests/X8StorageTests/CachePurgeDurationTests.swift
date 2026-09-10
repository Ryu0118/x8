import Testing
import X8Storage

@Suite("Cache purge duration parsing")
struct CachePurgeDurationTests {
    @Test(arguments: ["500ms", "30s", "2m", "1h", "7d"])
    func acceptsSupportedUnits(_ source: String) throws {
        _ = try CachePurgeDurationParser.parse(source)
    }

    @Test(arguments: ["", "30", "30w", "ms", "1 s"])
    func rejectsUnsupportedFormats(_ source: String) {
        #expect(throws: CachePurgeDurationError.invalidFormat) {
            _ = try CachePurgeDurationParser.parse(source)
        }
    }

    @Test(arguments: ["-1s", "nans", "infs"])
    func rejectsInvalidValues(_ source: String) {
        #expect(throws: CachePurgeDurationError.invalidValue) {
            _ = try CachePurgeDurationParser.parse(source)
        }
    }
}
