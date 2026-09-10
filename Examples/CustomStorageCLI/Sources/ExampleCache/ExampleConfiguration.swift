import CryptoKit
import Foundation
import X8CLI

struct ExampleConfiguration: Sendable {
    let domain: String

    static func load() async throws -> X8CLIConfiguration<Self> {
        guard let domain = ProcessInfo.processInfo.environment["EXAMPLE_CACHE_DOMAIN"], !domain.isEmpty else {
            throw ExampleConfigurationError.missingDomain
        }
        let digest = SHA256.hash(data: Data(domain.utf8))
        let profileID = "memory-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return try X8CLIConfiguration(
            value: Self(domain: domain),
            profileID: profileID,
            displayFields: [("domain", domain), ("profile_id", profileID), ("persistence", "none")],
            credentialSource: "none",
            storageDescription: "in-memory domain=\(domain)"
        )
    }
}

private enum ExampleConfigurationError: Error, CustomStringConvertible {
    case missingDomain

    var description: String {
        "Set EXAMPLE_CACHE_DOMAIN to select a demonstration cache domain."
    }
}
