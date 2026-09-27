#if X8_S3
    import FileManagerProtocol
    import Foundation
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

        /// The signed API store, or `nil` for a public-read-only profile.
        package let api: S3APIObjectStore?
        /// The immutable category key space shared by all storage conformances.
        package let keySpace: S3StorageKeySpace
        /// The reader used for Xcode-path CAS and Action Cache reads.
        private let reader: any S3ObjectReader
        private let fileManager: any FileManagerProtocol
        private var liveAPIClient: S3LiveAPIClient?
        private var livePublicTransport: AsyncHTTPPublicTransport?
        private let casDeduplicator = S3UploadDeduplicator<CASDataID>()
        private let actionCacheDeduplicator = S3UploadDeduplicator<ActionCacheDedupeKey>()

        /// Whether this instance owns a Soto client; `false` for a public-read-only profile.
        package var ownsSignedAPIClient: Bool {
            liveAPIClient != nil
        }

        /// Creates a storage backend backed by AWS S3 or an S3-compatible endpoint.
        ///
        /// Client construction is lazy with respect to network activity: this
        /// initializer configures clients but does not perform a cache request.
        /// Soto and its credential provider are created only when
        /// `configuration.api` is present, so a public-read-only profile never
        /// resolves credentials. Call `shutdown()` when the owning application
        /// is finished with the actor if its lifetime is shorter than the
        /// process.
        ///
        /// - Parameters:
        ///   - configuration: The signed API access and/or public read URL
        ///     for this cache domain.
        ///   - fileManager: Filesystem dependency used for bounded CAS staging
        ///     files.
        package init(
            configuration: S3StorageConfiguration,
            fileManager: any FileManagerProtocol = FileManager.default
        ) {
            let liveAPIClient = configuration.api.map {
                S3LiveAPIClient(
                    configuration: $0,
                    maximumConnectionsPerHost: configuration.maximumConnectionsPerHost,
                    maximumConcurrentOperations: configuration.maximumConcurrentOperations
                )
            }
            let livePublicTransport = configuration.publicReadURL.map { _ in
                AsyncHTTPPublicTransport(maximumConnectionsPerHost: configuration.maximumConnectionsPerHost)
            }
            self.init(
                configuration: configuration,
                api: liveAPIClient?.store,
                publicTransport: livePublicTransport,
                fileManager: fileManager,
                liveAPIClient: liveAPIClient,
                livePublicTransport: livePublicTransport
            )
        }

        /// Creates a storage backend with injected clients.
        ///
        /// This initializer is the package test boundary. It skips Soto and
        /// client ownership while retaining the same key, envelope, stream,
        /// and concurrency behavior as the live backend. `objectClient` is
        /// bound to `configuration.api`'s bucket; `publicTransport` must be
        /// supplied when `configuration.publicReadURL` is set.
        package init(
            configuration: S3StorageConfiguration,
            objectClient: (any S3ObjectClient)?,
            publicTransport: (any S3PublicHTTPTransport)? = nil,
            fileManager: any FileManagerProtocol = FileManager.default
        ) {
            let api = configuration.api.flatMap { api in
                objectClient.map { S3APIObjectStore(client: $0, bucket: api.bucket) }
            }
            self.init(
                configuration: configuration,
                api: api,
                publicTransport: publicTransport,
                fileManager: fileManager,
                liveAPIClient: nil,
                livePublicTransport: nil
            )
        }

        private init(
            configuration: S3StorageConfiguration,
            api: S3APIObjectStore?,
            publicTransport: (any S3PublicHTTPTransport)?,
            fileManager: any FileManagerProtocol,
            liveAPIClient: S3LiveAPIClient?,
            livePublicTransport: AsyncHTTPPublicTransport?
        ) {
            self.configuration = configuration
            self.api = api
            reader = Self.makeReader(configuration: configuration, api: api, publicTransport: publicTransport)
            keySpace = S3StorageKeySpace()
            self.fileManager = fileManager
            self.liveAPIClient = liveAPIClient
            self.livePublicTransport = livePublicTransport
        }

        /// Shuts down the clients this instance owns.
        ///
        /// The operation is idempotent. The injected-client initializer has no
        /// live clients to shut down.
        package func shutdown() async throws {
            if let liveAPIClient {
                try await liveAPIClient.shutdown()
                self.liveAPIClient = nil
            }
            if let livePublicTransport {
                try await livePublicTransport.shutdown()
                self.livePublicTransport = nil
            }
        }

        /// Returns the signed API store, or throws when this profile has none.
        package nonisolated func requiredAPI(for operation: String) throws -> S3APIObjectStore {
            guard let api else { throw S3APINotConfiguredError(operation: operation) }
            return api
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
            guard let stream = try await reader.get(
                key: keySpace.actionCache(key: key.rawValue),
                kind: .actionCache
            ) else { return nil }
            let data = try await ByteStreamSupport.collect(
                stream,
                maximumBytes: Self.maximumBufferedObjectBytes
            )
            return try S3StorageCodec.decodeActionCache(data)
        }

        /// Replaces the action-cache value for a key.
        package func putValue(_ value: ActionCacheValue, for key: ActionCacheKey) async throws {
            let api = try requiredAPI(for: "Cache writes")
            let dedupeKey = ActionCacheDedupeKey(key: key, value: value)
            try await actionCacheDeduplicator.withDeduplication(key: dedupeKey) { [api, keySpace] in
                let data = S3StorageCodec.encodeActionCache(value)
                try await api.put(
                    key: keySpace.actionCache(key: key.rawValue),
                    body: ByteStreamSupport.make(data),
                    contentLength: Int64(data.count)
                )
            }
        }

        deinit {
            liveAPIClient?.syncShutdown()
            livePublicTransport?.syncShutdown()
        }

        /// Reads the provider envelope and returns references plus a lazy payload stream.
        package func getCASRecord(
            id: CASDataID
        ) async throws -> (references: [CASDataID], bytes: ByteStream)? {
            guard let stream = try await reader.get(
                key: keySpace.cas(id: id.rawValue),
                kind: .cas
            ) else { return nil }
            return try await S3StorageCodec.decodeCASHeader(from: stream)
        }

        private func storeCAS(
            bytes: ByteStream,
            references: [CASDataID]
        ) async throws -> CASDataID {
            let api = try requiredAPI(for: "Cache writes")
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

            try await casDeduplicator.withDeduplication(key: id) { [api, keySpace] in
                let payload = try staged.stream()
                let body = ByteStreamSupport.prepend(
                    header,
                    to: payload
                )
                try await api.put(
                    key: keySpace.cas(id: id.rawValue),
                    body: body,
                    contentLength: Int64(header.count) + staged.byteCount
                )
            }
            return id
        }
    }

    private extension S3Storage {
        static func makeReader(
            configuration: S3StorageConfiguration,
            api: S3APIObjectStore?,
            publicTransport: (any S3PublicHTTPTransport)?
        ) -> any S3ObjectReader {
            if let baseURL = configuration.publicReadURL {
                guard let publicTransport else {
                    preconditionFailure("A public read URL needs a public transport")
                }
                return S3PublicURLObjectReader(
                    baseURL: baseURL,
                    transport: publicTransport,
                    maximumConcurrentOperations: configuration.maximumConcurrentOperations
                )
            }
            guard let api else {
                preconditionFailure("S3 storage without a public read URL needs signed API access")
            }
            return api
        }
    }
#endif
