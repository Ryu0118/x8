import Testing
@testable import X8Config

@Suite("Remote cache credentials redact secrets from their string representation")
struct RemoteCacheCredentialsTests {
    @Test
    func descriptionRedactsSecretAccessKeyAndSessionToken() {
        let credentials = RemoteCacheCredentials(
            accessKeyID: "AKIAEXAMPLE",
            secretAccessKey: "super-secret-value",
            sessionToken: "temporary-token"
        )

        let description = credentials.description

        #expect(description.contains("AKIAEXAMPLE"))
        #expect(!description.contains("super-secret-value"))
        #expect(!description.contains("temporary-token"))
        #expect(description.contains("<redacted>"))
    }

    @Test
    func descriptionReportsNilSessionTokenWithoutRedactingIt() {
        let credentials = RemoteCacheCredentials(
            accessKeyID: "AKIAEXAMPLE",
            secretAccessKey: "super-secret-value"
        )

        #expect(credentials.description.contains("sessionToken: nil"))
    }

    @Test
    func debugDescriptionMatchesDescription() {
        let credentials = RemoteCacheCredentials(
            accessKeyID: "AKIAEXAMPLE",
            secretAccessKey: "super-secret-value"
        )

        #expect(credentials.debugDescription == credentials.description)
    }

    @Test
    func stringInterpolationRedactsSecrets() {
        let credentials = RemoteCacheCredentials(
            accessKeyID: "AKIAEXAMPLE",
            secretAccessKey: "super-secret-value",
            sessionToken: "temporary-token"
        )

        let interpolated = "\(credentials)"

        #expect(!interpolated.contains("super-secret-value"))
        #expect(!interpolated.contains("temporary-token"))
    }
}
