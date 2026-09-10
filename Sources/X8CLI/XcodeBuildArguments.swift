import Foundation

/// Preserves the caller's build layout while adding the cache connection settings.
struct XcodeBuildArguments: Sendable {
    let values: [String]

    /// Stages disk-backed CAS responses on an explicitly selected DerivedData volume.
    /// This reads the argument without replacing it or choosing Xcode's default.
    var responseDirectory: URL? {
        guard let index = values.firstIndex(of: "-derivedDataPath"),
              values.indices.contains(index + 1)
        else { return nil }
        return URL(filePath: values[index + 1], directoryHint: .isDirectory)
    }

    func appending(cacheSettings: [String: String]) -> [String] {
        values + cacheSettings
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
    }
}
