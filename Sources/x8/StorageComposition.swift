#if X8_S3
    import X8Config
    import X8S3

    enum S3Composition {
        static func makeStorage(_ configuration: X8Configuration) async throws -> S3Storage {
            // Without s3.api no Soto client or credential provider is constructed at all.
            let api = configuration.api.map {
                S3APIConfiguration(
                    bucket: $0.bucket,
                    region: $0.region,
                    endpoint: $0.endpoint,
                    credentials: $0.credentials.staticCredentials
                )
            }
            return S3Storage(
                configuration: S3StorageConfiguration(
                    api: api,
                    publicReadURL: configuration.read.publicURL,
                    publishesReadProbes: configuration.write != .none
                )
            )
        }
    }
#endif
