import FileManagerProtocol
import Foundation

/// Locates and decodes raw `.x8.yml` layers from one caller-selected directory.
///
/// By default, the directory is the process current working directory. The
/// loader never parses forwarded `xcodebuild` arguments or searches parent
/// directories. It reads through the injected filesystem and overlays an
/// optional `.x8.local.yml`. It preserves optional and unresolved scalar values
/// for the next stage. It does not apply defaults, expand environment
/// parameters, validate provider values, or construct a storage backend.
package struct X8ConfigurationLoader: Sendable {
    private let fileManager: any FileManagerProtocol
    private let locator: X8ConfigurationLocator
    private let decoder: X8ConfigurationDecoder

    /// Creates a configuration loader.
    ///
    /// - Parameter fileManager: Filesystem dependency used to locate and read configuration files.
    package init(fileManager: any FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
        locator = X8ConfigurationLocator(fileManager: fileManager)
        decoder = X8ConfigurationDecoder(fileManager: fileManager)
    }

    /// Finds `.x8.yml`, decodes it, and applies an optional local override.
    ///
    /// The base file is required. A `.x8.local.yml` beside it is optional, and
    /// its non-`nil` fields replace the corresponding base fields. No resolved
    /// configuration is produced until `X8ConfigurationResolver` is called.
    ///
    /// - Parameter directory: The directory that must contain `.x8.yml`. If
    ///   omitted, the process current working directory is used.
    /// - Returns: The merged raw document, retaining unresolved scalar values.
    /// - Throws: `X8ConfigurationLoadingError` when the base or an existing
    ///   override is unreadable or invalid.
    package func load(
        from directory: URL? = nil
    ) async throws -> X8ConfigurationDocument {
        let directory = directory ?? defaultCurrentDirectory
        let configurationURL = try locator.findConfiguration(from: directory)
        let base = try decoder.decode(configurationURL)
        let localURL = configurationURL.deletingLastPathComponent()
            .appending(path: ".x8.local.yml")
        let local = try decoder.decodeIfPresent(localURL)
        return X8ConfigurationMerger.merge(base, local)
    }

    private var defaultCurrentDirectory: URL {
        URL(
            filePath: fileManager.currentDirectoryPath,
            directoryHint: .isDirectory
        )
    }
}
