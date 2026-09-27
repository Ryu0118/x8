#if X8_S3
    import X8Config
    import X8S3

    enum S3Composition {
        static func makeStorage(_ configuration: X8Configuration) async throws -> S3Storage {
            // Without s3.api no Soto client or credential provider is constructed at all.
            S3Storage(
                configuration: S3StorageConfiguration(
                    api: configuration.api,
                    publicReadURL: configuration.read.publicURL,
                    publishesReadProbes: configuration.write != .none
                )
            )
        }
    }
#endif
