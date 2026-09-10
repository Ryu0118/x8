import Foundation
import Testing
import X8Config

@Suite("X8ConfigurationPresentation redacts secrets")
struct X8ConfigurationPresentationTests {
    @Test
    func preservesOrderedFieldsForTheSharedCLI() {
        let configuration = X8Configuration(bucket: "foo-cache")
        let fields = X8ConfigurationPresentation.fields(configuration)
        #expect(fields.map(\.key) == ["version", "endpoint", "region", "bucket", "role", "profile_id", "credentials"])
        #expect(fields.map(\.value) == ["1", "<default>", "us-east-1", "foo-cache", "both", configuration.profileID, "default-provider"])
    }

    @Test("redacts static credentials and excludes runtime state")
    func redactsSecrets() throws {
        let endpoint = try #require(URL(string: "https://storage.example"))
        let configuration = X8Configuration(
            bucket: "foo-cache",
            endpoint: endpoint,
            role: .consumer,
            credentials: RemoteCacheCredentials(
                accessKeyID: "access-secret",
                secretAccessKey: "secret-value",
                sessionToken: "session-value"
            )
        )

        let output = X8ConfigurationPresentation.render(configuration)

        #expect(output.contains("credentials=static (redacted)"))
        #expect(output.contains("profile_id=" + configuration.profileID))
        #expect(output.contains("bucket=foo-cache"))
        #expect(output.contains("role=consumer"))
        #expect(!output.contains("access-secret"))
        #expect(!output.contains("secret-value"))
        #expect(!output.contains("session-value"))
        #expect(!output.contains("cache.sock"))
    }

    @Test("identifies the standard provider when credentials are absent")
    func identifiesDefaultCredentialProvider() {
        let configuration = X8Configuration(bucket: "foo-cache")

        #expect(
            X8ConfigurationPresentation.render(configuration)
                .contains("credentials=default-provider")
        )
    }
}
