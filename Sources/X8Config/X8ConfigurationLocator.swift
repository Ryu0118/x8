import FileManagerProtocol
import Foundation

/// Locates `.x8.yml` in one requested directory without reading its contents.
///
/// The loader's default directory is the process current working directory.
/// This boundary never parses forwarded `xcodebuild` arguments or searches
/// parent directories. The injected filesystem keeps lookup testable.
struct X8ConfigurationLocator: Sendable {
    private let fileManager: any FileManagerProtocol

    init(fileManager: any FileManagerProtocol) {
        self.fileManager = fileManager
    }

    func findConfiguration(from directory: URL) throws -> URL {
        let configuration = directory.appending(path: ".x8.yml")
        guard fileManager.fileExists(atPath: configuration.path) else {
            throw X8ConfigurationLoadingError.configurationFileNotFound(directory: directory)
        }
        return configuration
    }
}
