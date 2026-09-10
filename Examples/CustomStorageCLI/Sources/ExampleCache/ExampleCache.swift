import X8CLI

@main
struct ExampleCache {
    static func main() async {
        let cli = X8CLI(
            configuration: ExampleConfiguration.load,
            storage: { _ in ExampleMemoryStorage() }
        )
        await cli.main()
    }
}
