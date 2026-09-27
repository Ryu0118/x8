import Foundation
import Yams

/// Rejects keys outside the `.x8.yml` schema at every nesting level.
///
/// Synthesized `Codable` silently ignores unknown keys, so a typo such as
/// `s3.api.bucekt` would otherwise fall back to a default. The walk visits
/// only mappings the schema defines; a wrongly shaped value is left for the
/// decoder or resolver to report.
enum X8ConfigurationKeyValidator {
    private static let allowedKeys: [String: Set<String>] = [
        "": ["version", "s3", "socketPath"],
        "s3": ["api", "read", "write"],
        "s3.api": ["endpoint", "region", "bucket", "credentials"],
        "s3.api.credentials": ["source", "accessKeyID", "secretAccessKey", "sessionToken"],
        // Accepted in write too so the resolver can explain why a public-URL write is refused.
        "s3.read": ["publicURL"],
        "s3.write": ["publicURL"],
    ]

    /// Throws `unsupportedField` with the dotted path of the first unknown key.
    static func validate(_ root: Node, in url: URL) throws {
        guard let mapping = root.mapping else {
            throw X8ConfigurationLoadingError.invalidYAML(url)
        }
        try validate(mapping, path: "", in: url)
    }

    private static func validate(_ mapping: Node.Mapping, path: String, in url: URL) throws {
        guard let allowed = allowedKeys[path] else { return }
        try mapping.forEach { try validate(entry: $0, allowed: allowed, path: path, in: url) }
    }

    private static func validate(
        entry: (key: Node, value: Node),
        allowed: Set<String>,
        path: String,
        in url: URL
    ) throws {
        guard let key = entry.key.string else {
            throw X8ConfigurationLoadingError.invalidYAML(url)
        }
        let childPath = path.isEmpty ? key : "\(path).\(key)"
        guard allowed.contains(key) else {
            throw X8ConfigurationLoadingError.unsupportedField(url, childPath)
        }
        guard let child = entry.value.mapping else { return }
        try validate(child, path: childPath, in: url)
    }
}
