#if X8_S3
    import Foundation
    import X8Storage

    /// Maps X8 cache categories to object keys in one S3 bucket.
    ///
    /// CAS, Action Cache, staging, and retention keys each live under their
    /// own category prefix. Keeping that context in one value prevents
    /// callers from combining identifiers from different categories and
    /// avoids rebuilding the same category prefixes for every operation.
    package struct S3StorageKeySpace: Sendable {
        private let stagingBase = "staging/"
        private let actionCacheBase = "action-cache/"
        private let casBase = "cas/"
        private let retentionBase = "retention/"

        /// Creates the keyspace for one S3 bucket.
        package init() {}

        /// Builds the key for one CAS object.
        package func cas(id: Data) -> String {
            casBase + id.hexString
        }

        /// Builds the key for one Action Cache value.
        package func actionCache(key: Data) -> String {
            actionCacheBase + key.hexString
        }

        /// Builds the key for one incomplete upload.
        package func staging(identifier: Data) -> String {
            stagingBase + identifier.hexString
        }

        /// Builds the prefix for incomplete uploads.
        package var stagingPrefix: String {
            stagingBase
        }

        /// Builds the prefix for Action Cache values.
        package var actionCachePrefix: String {
            actionCacheBase
        }

        /// Builds the prefix for CAS objects.
        package var casPrefix: String {
            casBase
        }

        /// Builds the prefix for X8-owned retention anchors.
        package var retentionPrefix: String {
            retentionBase
        }

        /// Returns the object prefix for one administrative namespace.
        package func prefix(for kind: CacheObjectKind) -> String {
            switch kind {
            case .staging:
                stagingBase
            case .actionCache:
                actionCacheBase
            case .cas:
                casBase
            }
        }

        /// Extracts an opaque identifier from an object key in one namespace.
        package func identifier(
            from key: String,
            for kind: CacheObjectKind
        ) -> Data? {
            Self.identifier(from: key, after: prefix(for: kind))
        }

        /// Returns whether metadata describes the exact key for its namespace and identifier.
        package func matches(_ object: CacheObject) -> Bool {
            let expectedKey: String = switch object.kind {
            case .staging:
                staging(identifier: object.identifier)
            case .actionCache:
                actionCache(key: object.identifier)
            case .cas:
                cas(id: object.identifier)
            }
            return object.key == expectedKey
        }

        /// Builds the key for one X8-owned retention anchor.
        package func retention(identifier: Data) -> String {
            retentionBase + identifier.hexString
        }

        /// Extracts a retention-anchor identifier from a provider key.
        package func retentionIdentifier(from key: String) -> Data? {
            Self.identifier(from: key, after: retentionBase)
        }

        /// Builds the marker key that enables authoritative CAS retention scans.
        package var authorityMarkerKey: String {
            retentionBase + ".authoritative"
        }

        private static func identifier(from key: String, after base: String) -> Data? {
            guard key.hasPrefix(base) else { return nil }
            return Data(hexString: String(key.dropFirst(base.count)))
        }
    }

    private extension Data {
        init?(hexString: String) {
            guard hexString.count.isMultiple(of: 2) else { return nil }
            let bytes = stride(from: 0, to: hexString.count, by: 2).map { offset in
                let start = hexString.index(hexString.startIndex, offsetBy: offset)
                let end = hexString.index(start, offsetBy: 2)
                return UInt8(hexString[start ..< end], radix: 16)
            }
            guard bytes.allSatisfy({ $0 != nil }) else { return nil }
            self.init(bytes.compactMap(\.self))
        }

        var hexString: String {
            let digits: [UInt8] = Array("0123456789abcdef".utf8)
            var scalars = [UInt8]()
            scalars.reserveCapacity(count * 2)
            for byte in self {
                scalars.append(digits[Int(byte >> 4)])
                scalars.append(digits[Int(byte & 0x0F)])
            }
            return String(decoding: scalars, as: UTF8.self)
        }
    }
#endif
