import Testing
@testable import X8Config

@Suite("Scalar parameter expansion")
struct ScalarParameterExpanderTests {
    @Test
    func expandsDefaultsAlternativesAndEscapedDollars() throws {
        var expander = ScalarParameterExpander(environment: [
            "EMPTY": "",
            "SET": "value",
        ])

        let result = try expander.expand(
            "${UNSET-fallback},${EMPTY:-fallback},${SET+alternative},${SET:+nonempty},$$"
        )

        #expect(result == "fallback,fallback,alternative,nonempty,$")
    }

    @Test
    func assignmentAndInspectionFormsUseTheLocalEnvironment() throws {
        var expander = ScalarParameterExpander(environment: [
            "VALUE": "foo/foo-bar",
        ])

        let result = try expander.expand(
            "${BUCKET:=foo-cache},${#VALUE},$BUCKET"
        )

        #expect(result == "foo-cache,11,foo-cache")
    }

    @Test
    func removesShortestAndLongestGlobPatterns() throws {
        var expander = ScalarParameterExpander(environment: [
            "VALUE": "foo/foo-bar",
        ])

        let result = try expander.expand(
            "${VALUE#foo*},${VALUE##foo*},${VALUE%*bar},${VALUE%%*bar}"
        )

        #expect(result == "/foo-bar,,foo/foo-,")
    }

    @Test(arguments: [
        "$(command)",
        "`command`",
        "${",
        "${VALUE",
        "$1",
        "$?",
        "$@",
        "$*",
        "$#",
        "$-",
        "foo|bar",
    ])
    func rejectsUnsupportedExpansionSyntax(_ source: String) {
        var expander = ScalarParameterExpander(environment: [:])

        #expect(throws: X8ConfigurationResolutionError.unsupportedExpansion) {
            _ = try expander.expand(source)
        }
    }

    @Test
    func rejectsMissingRequiredValues() {
        var expander = ScalarParameterExpander(environment: [:])

        #expect(throws: X8ConfigurationResolutionError.requiredEnvironmentVariable("MISSING")) {
            _ = try expander.expand("${MISSING:?required}")
        }
    }

    @Test
    func rejectsExcessiveNesting() {
        var expander = ScalarParameterExpander(environment: [:])
        let nested = String(repeating: "${VALUE:-", count: 34) + String(repeating: "}", count: 34)

        #expect(throws: X8ConfigurationResolutionError.expansionDepthExceeded) {
            _ = try expander.expand(nested)
        }
    }
}
