import ArgumentParser
import X8Storage

/// Parses `--scope` as one of `CachePurgeScope`'s kebab-case argument spellings.
struct CachePurgeScopeArgument: ExpressibleByArgument {
    let value: CachePurgeScope

    init?(argument: String) {
        guard let value = CachePurgeScope.allCases.first(where: { Self.kebabCase(for: $0) == argument }) else {
            return nil
        }
        self.value = value
    }

    static var allValueStrings: [String] {
        CachePurgeScope.allCases.map(kebabCase(for:))
    }

    private static func kebabCase(for scope: CachePurgeScope) -> String {
        switch scope {
        case .staging: "staging"
        case .actionCache: "action-cache"
        case .cas: "cas"
        }
    }
}
