#if X8_S3
    import Foundation
    import Synchronization
    import Testing
    import X8Config
    import X8Core
    @testable import X8S3
    import X8Storage

    @Suite("S3 public-read probes turn only proven AccessDenied responses into misses")
    struct S3PublicReadProbeTests {
        private static let baseURL = "https://cache.example.com/team-cache/"
        private static let accessDenied = Data(
            "<?xml version=\"1.0\"?><Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>".utf8
        )

        private static func publicOnlyStorage(transport: FakePublicHTTPTransport) throws -> S3Storage {
            try S3Storage(
                configuration: .init(api: nil, publicReadURL: #require(URL(string: baseURL))),
                objectClient: nil,
                publicTransport: transport
            )
        }

        @Test
        func treatsAccessDeniedAsMissOnceProbeIsReadable() async throws {
            let transport = FakePublicHTTPTransport()
            await transport.respond(to: Self.baseURL + "cas/aa", status: 403, body: Self.accessDenied)
            await transport.respond(to: Self.baseURL + "cas/_x8-probe", status: 200)
            let storage = try Self.publicOnlyStorage(transport: transport)

            let object = try await storage.get(id: CASDataID(rawValue: Data([0xAA])))

            #expect(object == nil)
        }

        @Test
        func throwsAccessDeniedWhenProbeIsNotReadable() async throws {
            let transport = FakePublicHTTPTransport()
            await transport.respond(to: Self.baseURL + "action-cache/01", status: 403, body: Self.accessDenied)
            await transport.respond(to: Self.baseURL + "action-cache/_x8-probe", status: 403, body: Self.accessDenied)
            let storage = try Self.publicOnlyStorage(transport: transport)

            await #expect(throws: S3PublicReadError.self) {
                _ = try await storage.getValue(for: ActionCacheKey(rawValue: Data([0x01])))
            }
        }

        @Test
        func throwsForNonS3ForbiddenBodyEvenWhenProbeIsReadable() async throws {
            let transport = FakePublicHTTPTransport()
            await transport.respond(to: Self.baseURL + "cas/aa", status: 403, body: Data("<html>blocked</html>".utf8))
            await transport.respond(to: Self.baseURL + "cas/_x8-probe", status: 200)
            let storage = try Self.publicOnlyStorage(transport: transport)

            await #expect(throws: S3PublicReadError.self) {
                _ = try await storage.load(id: CASDataID(rawValue: Data([0xAA])))
            }
            #expect(await transport.requestedURLs == [Self.baseURL + "cas/aa"])
        }

        @Test
        func verifierReusesVerdictUntilRevalidationInterval() async throws {
            let transport = FakePublicHTTPTransport()
            await transport.respond(to: Self.baseURL + "cas/_x8-probe", status: 200)
            let clock = TestInstant()
            let verifier = try S3PublicReadVerifier(
                baseURL: #require(URL(string: Self.baseURL)),
                keySpace: S3StorageKeySpace(),
                transport: transport,
                revalidationInterval: .seconds(60),
                now: { clock.now }
            )

            #expect(await verifier.isReadable(.cas))
            await transport.respond(to: Self.baseURL + "cas/_x8-probe", status: 404)
            clock.advance(by: .seconds(59))
            #expect(await verifier.isReadable(.cas))
            clock.advance(by: .seconds(2))
            #expect(await verifier.isReadable(.cas) == false)
            #expect(await transport.requestedURLs.count == 2)
        }

        @Test
        func writerPublishesEachProbeOnce() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(api: X8S3APIConfiguration(bucket: "foo"), publishesReadProbes: true),
                objectClient: client
            )

            try await storage.putValue(ActionCacheValue(entries: ["a": Data([0x01])]), for: ActionCacheKey(rawValue: Data([0x01])))
            try await storage.putValue(ActionCacheValue(entries: ["a": Data([0x02])]), for: ActionCacheKey(rawValue: Data([0x02])))

            #expect(await client.value(for: "action-cache/_x8-probe") == S3ReadProbePublisher.probeBody)
            #expect(await client.value(for: "cas/_x8-probe") == nil)
            #expect(await client.putCallCount == 3)
        }

        @Test
        func writeOnlyCredentialStillPublishesProbeOnce() async throws {
            let client = FakeS3ObjectClient()
            await client.setDeniesGets(true)
            let storage = S3Storage(
                configuration: .init(api: X8S3APIConfiguration(bucket: "foo"), publishesReadProbes: true),
                objectClient: client
            )

            _ = try await storage.save(TestByteStream.make([Data([0x01])]))
            _ = try await storage.save(TestByteStream.make([Data([0x02])]))

            #expect(await client.value(for: "cas/_x8-probe") == S3ReadProbePublisher.probeBody)
            #expect(await client.putCallCount == 3)
            #expect(await client.requestedByteRanges.count == 1)
        }

        @Test
        func writerKeepsAnExistingProbe() async {
            let client = FakeS3ObjectClient()
            await client.seed([Data("existing".utf8)], for: "cas/_x8-probe")
            let publisher = S3ReadProbePublisher(
                api: S3APIObjectStore(client: client, bucket: "foo"),
                keySpace: S3StorageKeySpace()
            )

            await publisher.publishProbe(for: .cas)

            #expect(await client.putCallCount == 0)
        }

        @Test
        func listingSkipsProbeObjects() async throws {
            let client = FakeS3ObjectClient()
            let storage = S3Storage(
                configuration: .init(api: X8S3APIConfiguration(bucket: "foo"), publishesReadProbes: true),
                objectClient: client
            )
            _ = try await storage.save(TestByteStream.make([Data([0x01])]))

            let objects = try await storage.listObjects(of: .cas)

            #expect(objects.count == 1)
            #expect(await client.value(for: "cas/_x8-probe") != nil)
        }
    }

    /// A manually advanced clock reading shared with a verifier.
    final class TestInstant: Sendable {
        private let instant = Mutex(ContinuousClock.now)

        var now: ContinuousClock.Instant {
            instant.withLock { $0 }
        }

        func advance(by duration: Duration) {
            instant.withLock { $0 = $0.advanced(by: duration) }
        }
    }
#endif
