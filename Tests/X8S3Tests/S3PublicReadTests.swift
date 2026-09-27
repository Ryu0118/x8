#if X8_S3
    import Foundation
    import Testing
    import X8Config
    import X8Core
    @testable import X8S3
    import X8Storage

    @Suite("S3 public-URL reads stay unsigned and keep misses distinct from denials")
    struct S3PublicReadTests {
        private static let baseURL = "https://cache.example.com/team-cache/"

        private static func publicOnlyStorage(
            transport: FakePublicHTTPTransport
        ) throws -> S3Storage {
            try S3Storage(
                configuration: .init(api: nil, publicReadURL: #require(URL(string: baseURL))),
                objectClient: nil,
                publicTransport: transport
            )
        }

        @Test
        func readsCASObjectFromPublicURL() async throws {
            let transport = FakePublicHTTPTransport()
            let id = CASDataID(rawValue: Data([0xAA]))
            let references = [CASDataID(rawValue: Data([0xBB]))]
            let envelope = S3StorageCodec.encodeCAS(S3CASRecord(bytes: Data([0x01, 0x02]), references: references))
            await transport.respond(to: Self.baseURL + "cas/aa", status: 200, body: envelope)
            let storage = try Self.publicOnlyStorage(transport: transport)

            let object = try #require(try await storage.get(id: id))

            #expect(try await TestByteStream.collect(object.bytes) == Data([0x01, 0x02]))
            #expect(object.references == references)
        }

        @Test
        func readsActionCacheValueFromPublicURL() async throws {
            let transport = FakePublicHTTPTransport()
            let value = ActionCacheValue(entries: ["result": Data([0x07])])
            await transport.respond(
                to: Self.baseURL + "action-cache/01",
                status: 200,
                body: S3StorageCodec.encodeActionCache(value)
            )
            let storage = try Self.publicOnlyStorage(transport: transport)

            let loaded = try await storage.getValue(for: ActionCacheKey(rawValue: Data([0x01])))

            #expect(loaded == value)
        }

        @Test
        func treatsNotFoundAsCacheMiss() async throws {
            let transport = FakePublicHTTPTransport()
            await transport.respond(to: Self.baseURL + "cas/aa", status: 404)
            let storage = try Self.publicOnlyStorage(transport: transport)

            let object = try await storage.get(id: CASDataID(rawValue: Data([0xAA])))

            #expect(object == nil)
        }

        @Test
        func throwsForbiddenInsteadOfReportingAMiss() async throws {
            let transport = FakePublicHTTPTransport()
            await transport.respond(to: Self.baseURL + "action-cache/01", status: 403)
            let storage = try Self.publicOnlyStorage(transport: transport)

            await #expect(throws: S3PublicReadError.self) {
                _ = try await storage.getValue(for: ActionCacheKey(rawValue: Data([0x01])))
            }
        }

        @Test
        func throwsUnexpectedStatus() async throws {
            let transport = FakePublicHTTPTransport()
            await transport.respond(to: Self.baseURL + "cas/aa", status: 500)
            let storage = try Self.publicOnlyStorage(transport: transport)

            await #expect(throws: S3PublicReadError.unexpectedStatus(key: "cas/aa", status: 500)) {
                _ = try await storage.load(id: CASDataID(rawValue: Data([0xAA])))
            }
        }

        @Test
        func rejectsWritesWithoutSignedAPI() async throws {
            let storage = try Self.publicOnlyStorage(transport: FakePublicHTTPTransport())

            await #expect(throws: S3APINotConfiguredError(operation: "Cache writes")) {
                try await storage.putValue(
                    ActionCacheValue(entries: [:]),
                    for: ActionCacheKey(rawValue: Data([0x01]))
                )
            }
        }

        @Test
        func rejectsAdministrationWithoutSignedAPI() async throws {
            let storage = try Self.publicOnlyStorage(transport: FakePublicHTTPTransport())

            await #expect(throws: S3APINotConfiguredError(operation: "Cache administration")) {
                _ = try await storage.listObjects(of: .cas)
            }
        }

        @Test
        func publicURLReadsTakePrecedenceOverSignedAPI() async throws {
            let client = FakeS3ObjectClient()
            let transport = FakePublicHTTPTransport()
            let storage = try S3Storage(
                configuration: .init(
                    api: X8S3APIConfiguration(bucket: "foo"),
                    publicReadURL: #require(URL(string: Self.baseURL))
                ),
                objectClient: client,
                publicTransport: transport
            )

            _ = try await storage.getValue(for: ActionCacheKey(rawValue: Data([0x01])))

            #expect(await transport.requestedURLs == [Self.baseURL + "action-cache/01"])
            #expect(await client.requestedByteRanges.isEmpty)
        }

        @Test
        func publicOnlyLiveStorageCreatesNoSignedClient() async throws {
            let storage = try S3Storage(
                configuration: .init(api: nil, publicReadURL: #require(URL(string: Self.baseURL)))
            )

            #expect(await storage.ownsSignedAPIClient == false)
            try await storage.shutdown()
        }

        @Test
        func publicRequestCarriesNoHeaders() throws {
            let request = try AsyncHTTPPublicTransport.request(for: #require(URL(string: Self.baseURL + "cas/aa")))

            #expect(request.headers.isEmpty)
            #expect(request.method == .GET)
        }
    }
#endif
