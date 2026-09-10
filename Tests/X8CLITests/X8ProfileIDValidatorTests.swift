import ArgumentParser
import Testing
@testable import X8CLI

@Suite("Runtime profile identities cannot escape their directory")
struct X8ProfileIDValidatorTests {
    @Test(arguments: ["a", "Z", "0", "-", "_", "gcs-cache_42", String(repeating: "a", count: 64)])
    func acceptsPortableComponents(profileID: String) throws {
        try X8ProfileIDValidator.validate(profileID)
    }

    @Test(arguments: [
        "", ".", "..", "../cache", "/cache", "cache/other", "cache\\other",
        "cache.sock", "cache name", "cache\n", "cache\0", "é", "キャッシュ", "Ａ", "🗄️",
        String(repeating: "a", count: 65),
    ])
    func rejectsUnsafeComponents(profileID: String) {
        #expect(throws: ValidationError.self) {
            try X8ProfileIDValidator.validate(profileID)
        }
    }

    @Test(arguments: Array(UInt8.min ... UInt8.max))
    func checksEveryByteAtTheBoundary(byte: UInt8) {
        let character = String(UnicodeScalar(byte))
        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".contains(character)
        let accepted = (try? X8ProfileIDValidator.validate(character)) != nil
        #expect(accepted == allowed)
    }

    @Test
    func appliesValidationDuringConfigurationConstruction() {
        #expect(throws: ValidationError.self) {
            try X8CLIConfiguration(value: (), profileID: "../escape")
        }
    }
}
