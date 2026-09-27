import Foundation
import Testing
import X8Config

@Suite("X8ConfigurationPresentation redacts secrets")
struct X8ConfigurationPresentationTests {
    @Test
    func preservesOrderedFieldsForTheSharedCLI() {
        let api = X8S3APIConfiguration(bucket: "foo-cache")
        let configuration = X8Configuration(api: api, read: .api, write: .api)
        let fields = X8ConfigurationPresentation.fields(configuration)

        #expect(fields.map(\.key) == ["version", "read", "write", "endpoint", "region", "bucket", "profile_id", "credentials"])
        #expect(fields.map(\.value) == [
            "1", "api", "api", "<default>", "us-east-1", "foo-cache", configuration.profileID, "default-chain",
        ])
    }

    @Test("redacts static credentials and excludes runtime state")
    func redactsSecrets() throws {
        let api = try X8S3APIConfiguration(
            endpoint: #require(URL(string: "https://storage.example")),
            bucket: "foo-cache",
            credentials: .static(RemoteCacheCredentials(
                accessKeyID: "access-secret",
                secretAccessKey: "secret-value",
                sessionToken: "session-value"
            ))
        )
        let configuration = X8Configuration(api: api, read: .none, write: .api)

        let output = X8ConfigurationPresentation.render(configuration)

        #expect(output.contains("credentials=static (redacted)"))
        #expect(output.contains("profile_id=" + configuration.profileID))
        #expect(output.contains("bucket=foo-cache"))
        #expect(output.contains("read=none"))
        #expect(!output.contains("access-secret"))
        #expect(!output.contains("secret-value"))
        #expect(!output.contains("session-value"))
        #expect(!output.contains("cache.sock"))
    }

    @Test("reports no credentials for a public-read-only profile")
    func reportsNoCredentialsWithoutAPI() throws {
        let configuration = try X8Configuration(
            read: .publicURL(#require(URL(string: "https://cache.example.com/"))),
            write: .none
        )

        let output = X8ConfigurationPresentation.render(configuration)

        #expect(output.contains("read=publicURL https://cache.example.com/"))
        #expect(output.contains("credentials=none (no s3.api)"))
        #expect(!output.contains("bucket="))
    }
}
