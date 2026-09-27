#if X8_S3
    import Foundation
    import Synchronization
    import X8Storage

    /// Publishes the per-namespace probe objects that public readers verify.
    ///
    /// The first successful write to a namespace in a process PUTs its probe;
    /// every later write returns after a lock check, so the write path never
    /// waits on another probe request. Publishing is best effort: the cache
    /// write already succeeded, and retrying would add a failing request to
    /// every upload. The PUT is idempotent, so no existence check is made;
    /// that also keeps write-only credentials working. Probe keys are not hex
    /// identifiers, so listing and purge skip them.
    package final class S3ReadProbePublisher: Sendable {
        /// The fixed probe body; readers check only the status code.
        package static let probeBody = Data("x8 public-read probe\n".utf8)

        private let api: S3APIObjectStore
        private let keySpace: S3StorageKeySpace
        private let claimed = Mutex<Set<CacheObjectKind>>([])

        /// Creates a publisher for one bucket.
        package init(api: S3APIObjectStore, keySpace: S3StorageKeySpace) {
            self.api = api
            self.keySpace = keySpace
        }

        /// Writes the probe for `kind` the first time it is called for that namespace.
        package func publishProbe(for kind: CacheObjectKind) async {
            guard claimed.withLock({ $0.insert(kind).inserted }) else { return }
            // Best effort: the caller's cache write already succeeded.
            try? await api.put(
                key: keySpace.probe(for: kind),
                body: ByteStreamSupport.make(Self.probeBody),
                contentLength: Int64(Self.probeBody.count)
            )
        }
    }
#endif
