import Foundation
import Testing
@testable import X8Config

@Suite("X8 configuration loading keeps raw values and rejects unknown keys")
struct X8ConfigurationTests {
    private static let apiConfiguration = """
    version: 1
    s3:
      api:
        bucket: $BUCKET
        credentials:
          source: static
          accessKeyID: $ACCESS_KEY
          secretAccessKey: $SECRET_KEY
      read: api
      write: api
    """

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
            try ConfigurationTestSupport.write(Self.apiConfiguration, to: parent.appending(path: ".x8.yml"))

            await #expect(throws: X8ConfigurationLoadingError.configurationFileNotFound(directory: nested)) {
                _ = try await X8ConfigurationLoader().load(from: nested)
            }
        }
    }

    @Test
    func loaderDecodesNestedValuesWithoutResolvingThem() async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            try ConfigurationTestSupport.write(Self.apiConfiguration, to: root.appending(path: ".x8.yml"))

            let document = try await X8ConfigurationLoader().load(from: root)

            #expect(document == X8ConfigurationDocument(
                version: 1,
                s3: X8S3Document(
                    api: X8S3APIDocument(
                        bucket: "$BUCKET",
                        credentials: X8CredentialsDocument(
                            source: "static",
                            accessKeyID: "$ACCESS_KEY",
                            secretAccessKey: "$SECRET_KEY"
                        )
                    ),
                    read: .token("api"),
                    write: .token("api")
                )
            ))
        }
    }

    @Test
    func loaderDecodesPublicURLReadPath() async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            try ConfigurationTestSupport.write(
                """
                version: 1
                s3:
                  read:
                    publicURL: https://cache.example.com/team-cache/
                  write: none
                """,
                to: root.appending(path: ".x8.yml")
            )

            let document = try await X8ConfigurationLoader().load(from: root)

            #expect(document.s3?.read == .map(publicURL: "https://cache.example.com/team-cache/"))
            #expect(document.s3?.write == .token("none"))
        }
    }

    @Test
    func localOverrideReplacesPathsWholeAndMergesAPIFields() async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            try ConfigurationTestSupport.write(Self.apiConfiguration, to: root.appending(path: ".x8.yml"))
            try ConfigurationTestSupport.write(
                """
                s3:
                  api:
                    region: ap-northeast-1
                    credentials:
                      source: defaultChain
                  read:
                    publicURL: https://cache.example.com/
                  write: none
                """,
                to: root.appending(path: ".x8.local.yml")
            )

            let document = try await X8ConfigurationLoader().load(from: root)

            #expect(document.s3?.api == X8S3APIDocument(
                region: "ap-northeast-1",
                bucket: "$BUCKET",
                credentials: X8CredentialsDocument(source: "defaultChain")
            ))
            #expect(document.s3?.read == .map(publicURL: "https://cache.example.com/"))
            #expect(document.s3?.write == .token("none"))
        }
    }

    @Test
    func loaderUsesInjectedFileManagerForFilesystemChecks() async throws {
        let fileManager = RecordingFileManager()

        try await ConfigurationTestSupport.withDirectory { root in
            try ConfigurationTestSupport.write(Self.apiConfiguration, to: root.appending(path: ".x8.yml"))

            _ = try await X8ConfigurationLoader(fileManager: fileManager).load(from: root)
        }

        #expect(fileManager.fileExistsPaths.contains { $0.hasSuffix("/.x8.yml") })
    }

    @Test(arguments: [
        ("version: 1\nbucket: foo\n", "bucket"),
        ("version: 1\ns3:\n  role: consumer\n", "s3.role"),
        ("version: 1\ns3:\n  api:\n    bucekt: foo\n", "s3.api.bucekt"),
        ("version: 1\ns3:\n  api:\n    credentials:\n      token: x\n", "s3.api.credentials.token"),
        ("version: 1\ns3:\n  read:\n    publicUrl: https://a/\n", "s3.read.publicUrl"),
    ])
    func loaderRejectsUnknownKeysWithTheirPath(source: String, path: String) async throws {
        try await ConfigurationTestSupport.withDirectory { root in
            let configurationURL = root.appending(path: ".x8.yml")
            try ConfigurationTestSupport.write(source, to: configurationURL)

            await #expect(throws: X8ConfigurationLoadingError.unsupportedField(configurationURL, path)) {
                _ = try await X8ConfigurationLoader().load(from: root)
            }
        }
    }
}
