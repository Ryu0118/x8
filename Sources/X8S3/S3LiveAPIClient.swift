#if X8_S3
    import AsyncHTTPClient
    import SotoS3

    /// Owns the Soto client stack for signed S3 API access.
    ///
    /// Constructing it resolves no credentials and performs no request; the
    /// credential provider runs on the first signed call. It exists only for
    /// profiles that configure signed API access.
    struct S3LiveAPIClient: Sendable {
        let store: S3APIObjectStore
        private let awsClient: AWSClient
        private let httpClient: HTTPClient

        init(
            configuration: S3APIConfiguration,
            maximumConnectionsPerHost: Int,
            maximumConcurrentOperations: Int
        ) {
            let credentialProvider: CredentialProviderFactory = configuration.credentials.map {
                .static(
                    accessKeyId: $0.accessKeyID,
                    secretAccessKey: $0.secretAccessKey,
                    sessionToken: $0.sessionToken
                )
            } ?? .default

            var httpConfiguration = HTTPClient.Configuration()
            httpConfiguration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = maximumConnectionsPerHost
            let httpClient = HTTPClient(
                eventLoopGroupProvider: .singleton,
                configuration: httpConfiguration
            )

            let awsClient = AWSClient(credentialProvider: credentialProvider, httpClient: httpClient)
            let service = S3(
                client: awsClient,
                region: .init(rawValue: configuration.region),
                endpoint: configuration.endpoint?.absoluteString,
                options: [.s3DisableChunkedUploads]
            )
            store = S3APIObjectStore(
                client: ThrottledS3ObjectClient(
                    wrapping: SotoS3ObjectClient(service: service),
                    maximumConcurrentOperations: maximumConcurrentOperations
                ),
                bucket: configuration.bucket
            )
            self.awsClient = awsClient
            self.httpClient = httpClient
        }

        func shutdown() async throws {
            try await awsClient.shutdown()
            try await httpClient.shutdown().get()
        }

        func syncShutdown() {
            // A deinitializer cannot report a shutdown failure; release the clients best effort.
            try? awsClient.syncShutdown()
            try? httpClient.syncShutdown()
        }
    }
#endif
