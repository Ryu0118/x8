#if X8_S3
    import Foundation
    import X8Storage

    /// Publishes the per-namespace probe objects that public readers verify.
    ///
    /// A writer publishes each namespace's probe at most once per process,
    /// after its first successful write there. Publishing is best effort: the
    /// cache write already succeeded, and a failed attempt is retried on the
    /// next write. Probe keys are not hex identifiers, so listing and purge
    /// skip them.
    package actor S3ReadProbePublisher {
        /// The fixed probe body; readers check only the status code.
        package static let probeBody = Data("x8 public-read probe\n".utf8)

        private let api: S3APIObjectStore
        private let keySpace: S3StorageKeySpace
        private var published: Set<CacheObjectKind> = []
        private var attempts: [CacheObjectKind: Task<Bool, Never>] = [:]

        /// Creates a publisher for one bucket.
        package init(api: S3APIObjectStore, keySpace: S3StorageKeySpace) {
            self.api = api
            self.keySpace = keySpace
        }

        /// Ensures the probe for `kind` exists, creating it when absent.
        package func publishProbe(for kind: CacheObjectKind) async {
            guard !published.contains(kind) else { return }
            if let attempt = attempts[kind] {
                _ = await attempt.value
                return
            }

            let key = keySpace.probe(for: kind)
            let attempt = Task { [api] in await Self.publish(key: key, api: api) }
            attempts[kind] = attempt
            let succeeded = await attempt.value
            attempts[kind] = nil
            if succeeded {
                published.insert(kind)
            }
        }

        private static func publish(key: String, api: S3APIObjectStore) async -> Bool {
            // Best effort: the caller's cache write already succeeded, and the next write retries.
            await (try? publishIfAbsent(key: key, api: api)) != nil
        }

        private static func publishIfAbsent(key: String, api: S3APIObjectStore) async throws {
            if let existing = try await api.get(key: key) {
                try await ByteStreamSupport.discard(existing)
                return
            }
            try await api.put(
                key: key,
                body: ByteStreamSupport.make(probeBody),
                contentLength: Int64(probeBody.count)
            )
        }
    }
#endif
