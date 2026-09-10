import X8CLI

@main
struct X8Main {
    static func main() async {
        #if X8_S3
            let cli = X8CLI(
                configuration: X8ConfigurationComposition.load,
                storage: S3Composition.makeStorage,
                shutdown: { try await $0.shutdown() }
            )
        #else
            let cli = X8CLI(
                configuration: X8ConfigurationComposition.load,
                storageUnavailable: "Build x8 with the S3 trait to use remote cache operations."
            )
        #endif
        await cli.main()
    }
}
