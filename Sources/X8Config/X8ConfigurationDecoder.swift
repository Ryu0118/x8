import FileManagerProtocol
import Foundation
import Yams

/// Decodes one X8 YAML document at the filesystem boundary.
///
/// The decoder also rejects unknown keys at every level because synthesized
/// `Codable` decoding otherwise ignores them. It does not locate files, merge
/// overlays, expand scalar values, or validate resolved provider settings.
/// The instance captures the filesystem used to read the complete YAML layer.
struct X8ConfigurationDecoder: Sendable {
    private let fileManager: any FileManagerProtocol

    init(fileManager: any FileManagerProtocol) {
        self.fileManager = fileManager
    }

    func decodeIfPresent(_ url: URL) throws -> X8ConfigurationDocument? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decode(url)
    }

    func decode(_ url: URL) throws -> X8ConfigurationDocument {
        let source = try readSource(from: url)
        try X8ConfigurationKeyValidator.validate(composeRoot(from: source, url: url), in: url)

        do {
            return try YAMLDecoder().decode(X8ConfigurationDocument.self, from: source)
        } catch {
            throw X8ConfigurationLoadingError.invalidYAML(url)
        }
    }

    private func readSource(from url: URL) throws -> String {
        guard let data = fileManager.contents(atPath: url.path),
              let source = String(data: data, encoding: .utf8)
        else {
            throw X8ConfigurationLoadingError.configurationFileUnreadable(url)
        }
        return source
    }

    private func composeRoot(from source: String, url: URL) throws -> Node {
        do {
            return try requireRoot(compose(yaml: source), url: url)
        } catch let error as X8ConfigurationLoadingError {
            throw error
        } catch {
            throw X8ConfigurationLoadingError.invalidYAML(url)
        }
    }

    private func requireRoot(_ node: Node?, url: URL) throws -> Node {
        guard let node else {
            throw X8ConfigurationLoadingError.invalidYAML(url)
        }
        return node
    }
}
