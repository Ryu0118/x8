import Foundation
import Testing
@testable import X8Config

@Suite("X8 configuration loading and resolution")
struct X8ConfigurationTests {
    @Test
    func loaderRequiresBaseConfiguration() async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            let nested = root.appending(path: "Sources", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

            await #expect(throws: X8ConfigurationLoadingError.configurationFileNotFound(directory: nested)) {
                _ = try await X8ConfigurationLoader().load(from: nested)
            }
        }
    }

    @Test
    func loaderOnlyChecksRequestedDirectory() async throws {
        try await ConfigurationTestSupport.withDirectory { parent in
            let nested = parent.appending(path: "Sources", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try ConfigurationTestSupport.write(
                "version: 1\nbucket: foo\n",
                to: parent.appending(path: ".x8.yml")
            )

            await #expect(throws: X8ConfigurationLoadingError.configurationFileNotFound(directory: nested)) {
                _ = try await X8ConfigurationLoader().load(from: nested)
            }
        }
    }

    @Test
    func loaderMergesLocalOverrideWithoutResolvingValues() async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            try ConfigurationTestSupport.write(
                """
                version: 1
                bucket: $BUCKET
                """,
                to: root.appending(path: ".x8.yml")
            )
            try ConfigurationTestSupport.write(
                """
                region: ap-northeast-1
                accessKeyID: $ACCESS_KEY
                secretAccessKey: $SECRET_KEY
                """,
                to: root.appending(path: ".x8.local.yml")
            )

            let document = try await X8ConfigurationLoader().load(from: root)

            #expect(document.version == 1)
            #expect(document.bucket == "$BUCKET")
            #expect(document.region == "ap-northeast-1")
            #expect(document.accessKeyID == "$ACCESS_KEY")
            #expect(document.secretAccessKey == "$SECRET_KEY")
        }
    }

    @Test
    func loaderMergesLocalOverrideForRole() async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            try ConfigurationTestSupport.write(
                """
                version: 1
                bucket: foo
                role: consumer
                """,
                to: root.appending(path: ".x8.yml")
            )
            try ConfigurationTestSupport.write(
                "role: producer",
                to: root.appending(path: ".x8.local.yml")
            )

            let document = try await X8ConfigurationLoader().load(from: root)

            #expect(document.role == .producer)
        }
    }

    @Test
    func loaderRejectsInvalidRole() async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            let configurationURL = root.appending(path: ".x8.yml")
            try ConfigurationTestSupport.write(
                "version: 1\nbucket: foo\nrole: bogus\n",
                to: configurationURL
            )

            await #expect(throws: X8ConfigurationLoadingError.invalidYAML(configurationURL)) {
                _ = try await X8ConfigurationLoader().load(from: root)
            }
        }
    }

    @Test
    func loaderUsesInjectedFileManagerForFilesystemChecks() async throws {
        let fileManager = RecordingFileManager()

        try await ConfigurationTestSupport.withDirectory { root in
            try ConfigurationTestSupport.write(
                "version: 1\nbucket: foo\n",
                to: root.appending(path: ".x8.yml")
            )

            _ = try await X8ConfigurationLoader(fileManager: fileManager).load(from: root)
        }

        #expect(fileManager.fileExistsPaths.contains { $0.hasSuffix("/.x8.yml") })
    }

    @Test
    func loaderRejectsUnknownFields() async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            let configurationURL = root.appending(path: ".x8.yml")
            try ConfigurationTestSupport.write(
                "version: 1\nbucket: foo\nunknown: value\n",
                to: configurationURL
            )

            await #expect(throws: X8ConfigurationLoadingError.unsupportedField(configurationURL, "unknown")) {
                _ = try await X8ConfigurationLoader().load(from: root)
            }
        }
    }

    @Test
    func resolverExpandsValuesAndAppliesDefaults() throws {
        let document = X8ConfigurationDocument(
            version: 1,
            bucket: "${BUCKET}",
            accessKeyID: "${ACCESS_KEY}",
            secretAccessKey: "${SECRET_KEY}",
            sessionToken: "${SESSION_TOKEN:-}"
        )

        let configuration = try X8ConfigurationResolver().resolve(
            document,
            environment: [
                "BUCKET": "foo-cache",
                "ACCESS_KEY": "access",
                "SECRET_KEY": "secret",
            ]
        )

        #expect(configuration.version == 1)
        #expect(configuration.bucket == "foo-cache")
        #expect(configuration.region == "us-east-1")
        #expect(configuration.role == .both)
        #expect(configuration.credentials == RemoteCacheCredentials(
            accessKeyID: "access",
            secretAccessKey: "secret"
        ))
    }

    @Test
    func resolverUsesExplicitRoleWithoutAffectingProfileID() throws {
        let producer = X8ConfigurationDocument(
            version: 1,
            bucket: "foo",
            role: .producer
        )
        let consumer = X8ConfigurationDocument(
            version: 1,
            bucket: "foo",
            role: .consumer
        )

        let resolvedProducer = try X8ConfigurationResolver().resolve(producer)
        let resolvedConsumer = try X8ConfigurationResolver().resolve(consumer)

        #expect(resolvedProducer.role == .producer)
        #expect(resolvedConsumer.role == .consumer)
        // Role gates writes at the storage boundary; it must not change the
        // cache-domain identity two differently-scoped invocations share.
        #expect(resolvedProducer.profileID == resolvedConsumer.profileID)
    }

    @Test
    func resolverRejectsIncompleteCredentials() {
        let document = X8ConfigurationDocument(
            version: 1,
            bucket: "foo",
            accessKeyID: "access"
        )

        #expect(throws: X8ConfigurationResolutionError.incompleteCredentials) {
            _ = try X8ConfigurationResolver().resolve(document)
        }
    }

    @Test
    func resolverRejectsNonLocalInsecureEndpoint() {
        let document = X8ConfigurationDocument(
            version: 1,
            endpoint: "http://storage.example",
            bucket: "foo"
        )

        #expect(throws: X8ConfigurationResolutionError.invalidField("endpoint")) {
            _ = try X8ConfigurationResolver().resolve(document)
        }
    }

    @Test
    func resolverRejectsEndpointCredentialsAndQuery() {
        let document = X8ConfigurationDocument(
            version: 1,
            endpoint: "https://user:secret@storage.example/cache?token=secret",
            bucket: "foo"
        )

        #expect(throws: X8ConfigurationResolutionError.invalidField("endpoint")) {
            _ = try X8ConfigurationResolver().resolve(document)
        }
    }
}
