#if X8_S3
    import AsyncHTTPClient
    import FileManagerProtocol
    import Foundation
    import SotoS3
    import X8Core
    import X8Storage

    /// An actor-isolated S3-compatible implementation of X8 cache storage.
    ///
    /// The actor maps provider-neutral CAS and Action Cache operations to one
    /// configured S3 bucket. It owns the live Soto client created by
    /// its public initializer and releases that client from `shutdown()` or
    /// deinitialization. CAS payloads are staged to a private local file so
    /// their opaque identifier can be computed before an upload and the body
    /// can be replayed if the provider request needs a retry.
    ///
    /// Administrative listing, conditional deletion, and retention methods are
    /// separate protocol conformances in this module. The storage actor does
    /// not choose purge policy; `X8Storage` owns that provider-neutral policy.
    package actor S3Storage: CASStore, ActionCacheStore {
        /// Bounds metadata values that the backend must decode in memory.
        package static let maximumBufferedObjectBytes = 16 * 1024 * 1024

        /// The resolved provider configuration shared by data and administration paths.
        package let configuration: S3StorageConfiguration

        /// The provider-neutral object client used by this storage actor.
        package let objectClient: any S3ObjectClient
        /// The immutable category key space shared by all storage conformances.
        package let keySpace: S3StorageKeySpace
        private let fileManager: any FileManagerProtocol
        private var awsClient: AWSClient?
        private var ownedHTTPClient: HTTPClient?
        private let casDeduplicator = S3UploadDeduplicator<CASDataID>()
        private let actionCacheDeduplicator = S3UploadDeduplicator<ActionCacheDedupeKey>()

        /// Creates a storage backend backed by AWS S3 or an S3-compatible endpoint.
        ///
        /// Client construction is lazy with respect to network activity: this
        /// initializer configures Soto but does not perform a cache request.
        /// Call `shutdown()` when the owning application is finished with the
        /// actor if its lifetime is shorter than the process.
        ///
        /// - Parameters:
        ///   - configuration: The bucket, endpoint, and credentials
        ///     for this cache domain.
        ///   - fileManager: Filesystem dependency used for bounded CAS staging
        ///     files.
        package init(
            configuration: S3StorageConfiguration,
            fileManager: any FileManagerProtocol = FileManager.default
        ) {
            let credentialProvider: CredentialProviderFactory = configuration.credentials.map {
                .static(
                    accessKeyId: $0.accessKeyID,
                    secretAccessKey: $0.secretAccessKey,
                    sessionToken: $0.sessionToken
                )
            } ?? .default

            var httpConfiguration = HTTPClient.Configuration()
            httpConfiguration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit =
                configuration.maximumConnectionsPerHost
            let httpClient = HTTPClient(
                eventLoopGroupProvider: .singleton,
                configuration: httpConfiguration
            )

            let client = AWSClient(credentialProvider: credentialProvider, httpClient: httpClient)
            let service = S3(
                client: client,
                region: .init(rawValue: configuration.region),
                endpoint: configuration.endpoint?.absoluteString,
                options: [.s3DisableChunkedUploads]
            )
            self.configuration = configuration
            objectClient = ThrottledS3ObjectClient(
                wrapping: SotoS3ObjectClient(service: service),
                maximumConcurrentOperations: configuration.maximumConcurrentOperations
            )
            keySpace = S3StorageKeySpace()
            self.fileManager = fileManager
            awsClient = client
            ownedHTTPClient = httpClient
        }

        /// Creates a storage backend with an injected object client.
        ///
        /// This initializer is the package test boundary. It skips Soto and
        /// AWS-client ownership while retaining the same key, envelope, stream,
        /// and concurrency behavior as the live backend.
        package init(
            configuration: S3StorageConfiguration,
            objectClient: any S3ObjectClient,
            fileManager: any FileManagerProtocol = FileManager.default
        ) {
            self.configuration = configuration
            self.objectClient = objectClient
            keySpace = S3StorageKeySpace()
            self.fileManager = fileManager
            awsClient = nil
            ownedHTTPClient = nil
        }

        /// Shuts down the underlying AWS and HTTP clients, when this instance owns them.
        ///
        /// The operation is idempotent. The injected-object-client initializer
        /// has no live clients to shut down.
        package func shutdown() async throws {
            if let awsClient {
                try await awsClient.shutdown()
                self.awsClient = nil
            }
            if let ownedHTTPClient {
                try await ownedHTTPClient.shutdown().get()
                self.ownedHTTPClient = nil
            }
        }

        /// Returns a CAS record, or `nil` when the identifier is absent.
        ///
        /// The provider envelope header is decoded before the payload is
        /// returned as a lazy stream. This allows reference metadata to be
        /// inspected without buffering the complete CAS object.
        package func get(id: CASDataID) async throws -> CASObject? {
            guard let record = try await getCASRecord(id: id) else { return nil }
            return CASObject(bytes: record.bytes, references: record.references)
        }

        /// Stores a CAS object and returns its backend-generated opaque identifier.
        package func put(_ object: CASObject) async throws -> CASDataID {
            try await storeCAS(bytes: object.bytes, references: object.references)
        }

        /// Returns CAS payload bytes, or `nil` when the identifier is absent.
        package func load(id: CASDataID) async throws -> ByteStream? {
            try await getCASRecord(id: id)?.bytes
        }

        /// Stores blob bytes and returns their backend-generated opaque identifier.
        package func save(_ bytes: ByteStream) async throws -> CASDataID {
            try await storeCAS(bytes: bytes, references: [])
        }

        /// Returns the action-cache value for a key, or `nil` when absent.
        package func getValue(for key: ActionCacheKey) async throws -> ActionCacheValue? {
            guard let stream = try await objectClient.get(
                bucket: configuration.bucket,
                key: keySpace.actionCache(key: key.rawValue)
            ) else { return nil }
            let data = try await ByteStreamSupport.collect(
                stream,
                maximumBytes: Self.maximumBufferedObjectBytes
            )
            return try S3StorageCodec.decodeActionCache(data)
        }

        /// Replaces the action-cache value for a key.
        package func putValue(_ value: ActionCacheValue, for key: ActionCacheKey) async throws {
            let dedupeKey = ActionCacheDedupeKey(key: key, value: value)
            try await actionCacheDeduplicator.withDeduplication(key: dedupeKey) { [objectClient, configuration, keySpace] in
                let data = S3StorageCodec.encodeActionCache(value)
                try await objectClient.put(
                    bucket: configuration.bucket,
                    key: keySpace.actionCache(key: key.rawValue),
                    body: ByteStreamSupport.make(data),
                    contentLength: Int64(data.count)
                )
            }
        }

        deinit {
            // A deinitializer cannot report an async shutdown failure; release the clients best effort.
            try? awsClient?.syncShutdown()
            try? ownedHTTPClient?.syncShutdown()
        }

        /// Reads the provider envelope and returns references plus a lazy payload stream.
        package func getCASRecord(
            id: CASDataID
        ) async throws -> (references: [CASDataID], bytes: ByteStream)? {
            guard let stream = try await objectClient.get(
                bucket: configuration.bucket,
                key: keySpace.cas(id: id.rawValue)
            ) else { return nil }
            return try await S3StorageCodec.decodeCASHeader(from: stream)
        }

        private func storeCAS(
            bytes: ByteStream,
            references: [CASDataID]
        ) async throws -> CASDataID {
            // The staged file makes the generated key deterministic and lets a retry replay the body.
            let staged = try await S3CASUpload.stage(
                bytes,
                fileManager: fileManager
            )
            let id = try await CASDataIDGenerator.id(
                for: staged.stream(),
                references: references
            )
            let header = S3StorageCodec.encodeCASHeader(references: references)

            try await casDeduplicator.withDeduplication(key: id) { [objectClient, configuration, keySpace] in
                let payload = try staged.stream()
                let body = ByteStreamSupport.prepend(
                    header,
                    to: payload
                )
                try await objectClient.put(
                    bucket: configuration.bucket,
                    key: keySpace.cas(id: id.rawValue),
                    body: body,
                    contentLength: Int64(header.count) + staged.byteCount
                )
            }
            return id
        }
    }
#endif
