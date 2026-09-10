#if X8_S3
    import X8Config
    import X8S3

    enum S3Composition {
        static func makeStorage(_ configuration: X8Configuration) async throws -> S3Storage {
            S3Storage(
                configuration: S3StorageConfiguration(
                    bucket: configuration.bucket,
                    region: configuration.region,
                    endpoint: configuration.endpoint,
                    credentials: configuration.credentials
                )
            )
        }
    }
#endif
