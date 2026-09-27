import Foundation
import Testing
@testable import X8Config

@Suite("X8 configuration resolution validates read and write paths together")
struct X8ConfigurationResolverTests {
    private static let api = X8S3APIDocument(bucket: "foo", credentials: X8CredentialsDocument(source: "defaultChain"))
    private static let publicURL = X8AccessPathDocument.map(publicURL: "https://cache.example.com/team-cache/")

    private static func resolve(
        api: X8S3APIDocument? = nil,
        read: X8AccessPathDocument?,
        write: X8AccessPathDocument?,
        environment: [String: String] = [:]
    ) throws -> X8Configuration {
        try X8ConfigurationResolver().resolve(
            X8ConfigurationDocument(version: 1, s3: X8S3Document(api: api, read: read, write: write)),
            environment: environment
        )
    }

    @Test
    func resolvesPublicReadWithoutAnyAPI() throws {
        let configuration = try Self.resolve(read: Self.publicURL, write: .token("none"))

        #expect(try configuration.read == .publicURL(#require(URL(string: "https://cache.example.com/team-cache/"))))
        #expect(configuration.write == .none)
        #expect(configuration.api == nil)
        #expect(configuration.role == .consumer)
    }

    @Test
    func resolvesPublicReadWithAPIWrite() throws {
        let configuration = try Self.resolve(api: Self.api, read: Self.publicURL, write: .token("api"))

        #expect(configuration.write == .api)
        #expect(configuration.api == X8S3APIConfiguration(bucket: "foo"))
        #expect(configuration.role == .both)
    }

    @Test
    func resolvesWriterAndAPIReader() throws {
        let writer = try Self.resolve(api: Self.api, read: .token("none"), write: .token("api"))
        let reader = try Self.resolve(api: Self.api, read: .token("api"), write: .token("none"))

        #expect(writer.role == .producer)
        #expect(reader.role == .consumer)
        // Paths gate access at the storage boundary; they must not change the cache-domain identity.
        #expect(writer.profileID == reader.profileID)
    }

    @Test
    func expandsAPIFieldsAndAppliesDefaults() throws {
        let configuration = try Self.resolve(
            api: X8S3APIDocument(
                bucket: "${BUCKET}",
                credentials: X8CredentialsDocument(
                    source: "static",
                    accessKeyID: "${ACCESS_KEY}",
                    secretAccessKey: "${SECRET_KEY}",
                    sessionToken: "${SESSION_TOKEN:-}"
                )
            ),
            read: .token("api"),
            write: .token("api"),
            environment: ["BUCKET": "foo-cache", "ACCESS_KEY": "access", "SECRET_KEY": "secret"]
        )

        #expect(configuration.api == X8S3APIConfiguration(
            region: "us-east-1",
            bucket: "foo-cache",
            credentials: .static(RemoteCacheCredentials(accessKeyID: "access", secretAccessKey: "secret"))
        ))
    }

    @Test
    func expandsPublicURL() throws {
        let configuration = try Self.resolve(
            read: .map(publicURL: "${CACHE_URL}"),
            write: .token("none"),
            environment: ["CACHE_URL": "http://127.0.0.1:9000/cache/"]
        )

        #expect(configuration.read.publicURL?.absoluteString == "http://127.0.0.1:9000/cache/")
    }

    @Test
    func profileIDIgnoresCredentials() throws {
        let chain = try Self.resolve(api: Self.api, read: .token("api"), write: .token("api"))
        let staticKeys = try Self.resolve(
            api: X8S3APIDocument(
                bucket: "foo",
                credentials: X8CredentialsDocument(source: "static", accessKeyID: "a", secretAccessKey: "s")
            ),
            read: .token("api"),
            write: .token("api")
        )

        #expect(chain.profileID == staticKeys.profileID)
    }

    @Test(arguments: [
        (nil, X8AccessPathDocument.token("api"), X8ConfigurationResolutionError.missingField("s3.read")),
        (.token("none"), nil, .missingField("s3.write")),
        (.token("none"), .token("none"), .readAndWriteDisabled),
        (.token("api"), .token("none"), .apiRequired("s3.read")),
        (.token("none"), .token("api"), .apiRequired("s3.write")),
        (.token("bogus"), .token("none"), .invalidField("s3.read", reason: "expected api, none, or publicURL: <url>")),
        (.map(publicURL: nil), .token("none"), .missingField("s3.read.publicURL")),
        (.token("none"), .token("publicURL"), .publicURLWrite),
        (.token("none"), .map(publicURL: "https://a.example/"), .publicURLWrite),
        (.token("none"), .token("bogus"), .invalidField("s3.write", reason: "expected api or none")),
    ] as [(X8AccessPathDocument?, X8AccessPathDocument?, X8ConfigurationResolutionError)])
    func rejectsInvalidPathCombinations(
        read: X8AccessPathDocument?,
        write: X8AccessPathDocument?,
        error: X8ConfigurationResolutionError
    ) {
        #expect(throws: error) {
            _ = try Self.resolve(read: read, write: write)
        }
    }

    @Test
    func rejectsUnusedAPI() {
        #expect(throws: X8ConfigurationResolutionError.unusedAPI) {
            _ = try Self.resolve(api: Self.api, read: Self.publicURL, write: .token("none"))
        }
    }

    @Test(arguments: [
        (X8CredentialsDocument(source: "static", accessKeyID: "a"), X8ConfigurationResolutionError.incompleteCredentials),
        (X8CredentialsDocument(source: "defaultChain", sessionToken: "t"), .defaultChainWithStaticFields),
        (X8CredentialsDocument(), .missingField("s3.api.credentials.source")),
        (X8CredentialsDocument(source: "env"), .invalidField("s3.api.credentials.source", reason: "expected static or defaultChain")),
    ])
    func rejectsInvalidCredentials(credentials: X8CredentialsDocument, error: X8ConfigurationResolutionError) {
        #expect(throws: error) {
            _ = try Self.resolve(
                api: X8S3APIDocument(bucket: "foo", credentials: credentials),
                read: .token("api"),
                write: .token("api")
            )
        }
    }

    @Test
    func requiresCredentialsBlock() {
        #expect(throws: X8ConfigurationResolutionError.missingField("s3.api.credentials")) {
            _ = try Self.resolve(api: X8S3APIDocument(bucket: "foo"), read: .token("api"), write: .token("api"))
        }
    }

    @Test(arguments: [
        "http://storage.example",
        "https://user:secret@storage.example/cache?token=secret",
        "ftp://storage.example",
    ])
    func rejectsInvalidEndpoint(endpoint: String) {
        let api = X8S3APIDocument(endpoint: endpoint, bucket: "foo", credentials: X8CredentialsDocument(source: "defaultChain"))

        #expect(throws: X8ConfigurationResolutionError.self) {
            _ = try Self.resolve(api: api, read: .token("api"), write: .token("api"))
        }
    }

    @Test(arguments: [
        "https://cache.example.com/team-cache",
        "http://cache.example.com/",
        "https://cache.example.com/?x=1",
    ])
    func rejectsInvalidPublicURL(url: String) {
        #expect(throws: X8ConfigurationResolutionError.self) {
            _ = try Self.resolve(read: .map(publicURL: url), write: .token("none"))
        }
    }

    @Test
    func expandsAbsoluteSocketPath() throws {
        let configuration = try X8ConfigurationResolver().resolve(
            X8ConfigurationDocument(
                version: 1,
                s3: X8S3Document(read: Self.publicURL, write: .token("none")),
                socketPath: "${HOME}/.x8/cache.sock"
            ),
            environment: ["HOME": "/Users/test"]
        )

        #expect(configuration.socketPath == "/Users/test/.x8/cache.sock")
    }

    @Test(arguments: ["relative/cache.sock", "/" + String(repeating: "a", count: 104)])
    func rejectsUnusableSocketPath(socketPath: String) {
        #expect(throws: X8ConfigurationResolutionError.invalidField(
            "socketPath",
            reason: "expected an absolute path shorter than 104 bytes"
        )) {
            _ = try X8ConfigurationResolver().resolve(X8ConfigurationDocument(
                version: 1,
                s3: X8S3Document(read: Self.publicURL, write: .token("none")),
                socketPath: socketPath
            ))
        }
    }

    @Test
    func rejectsUnsupportedVersionAndMissingS3() {
        #expect(throws: X8ConfigurationResolutionError.unsupportedVersion(2)) {
            _ = try X8ConfigurationResolver().resolve(X8ConfigurationDocument(version: 2))
        }
        #expect(throws: X8ConfigurationResolutionError.missingField("s3")) {
            _ = try X8ConfigurationResolver().resolve(X8ConfigurationDocument(version: 1))
        }
    }
}
