import X8CLI
import X8Config

enum X8ConfigurationComposition {
    static func load() async throws -> X8CLIConfiguration<X8Configuration> {
        let document = try await X8ConfigurationLoader().load()
        let configuration = try X8ConfigurationResolver().resolve(document)
        return try X8CLIConfiguration(
            value: configuration,
            profileID: configuration.profileID,
            role: configuration.role,
            displayFields: X8ConfigurationPresentation.fields(configuration),
            credentialSource: X8ConfigurationPresentation.credentialSource(configuration),
            storageDescription: storageDescription(configuration),
            socketPath: configuration.socketPath
        )
    }

    private static func storageDescription(_ configuration: X8Configuration) -> String {
        if let api = configuration.api {
            return "bucket=\(api.bucket)"
        }
        return "publicURL=\(configuration.read.publicURL?.absoluteString ?? "")"
    }
}
