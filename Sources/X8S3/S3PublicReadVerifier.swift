#if X8_S3
    import Foundation
    import X8Storage

    /// Decides whether an S3 `AccessDenied` 403 on a public URL means "absent".
    ///
    /// Without anonymous `s3:ListBucket`, S3 and MinIO answer a GET for a
    /// missing key with the same 403 `AccessDenied` as a real permission
    /// failure. Only after an unsigned GET of the namespace's probe object
    /// succeeds is anonymous read access proven, so a 403 can safely be
    /// treated as a miss. Verdicts are cached per namespace and re-checked at
    /// most once per `revalidationInterval`, so a revoked policy is noticed
    /// without probing on every miss. Probing happens only after a 403, so a
    /// provider that answers misses with 404 never probes.
    package actor S3PublicReadVerifier {
        private struct Verdict {
            let isReadable: Bool
            let checkedAt: ContinuousClock.Instant
        }

        private let baseURL: URL
        private let keySpace: S3StorageKeySpace
        private let transport: any S3PublicHTTPTransport
        private let revalidationInterval: Duration
        private let now: @Sendable () -> ContinuousClock.Instant
        private var verdicts: [CacheObjectKind: Verdict] = [:]
        private var probes: [CacheObjectKind: Task<Bool, Never>] = [:]

        /// Creates a verifier for one public URL prefix ending in `/`.
        package init(
            baseURL: URL,
            keySpace: S3StorageKeySpace,
            transport: any S3PublicHTTPTransport,
            revalidationInterval: Duration = .seconds(60),
            now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
        ) {
            self.baseURL = baseURL
            self.keySpace = keySpace
            self.transport = transport
            self.revalidationInterval = revalidationInterval
            self.now = now
        }

        /// Returns whether anonymous reads of `kind` are proven, probing when the verdict is stale.
        package func isReadable(_ kind: CacheObjectKind) async -> Bool {
            if let verdict = verdicts[kind], now() - verdict.checkedAt < revalidationInterval {
                return verdict.isReadable
            }
            if let probe = probes[kind] {
                return await probe.value
            }

            let url = URL(string: baseURL.absoluteString + keySpace.probe(for: kind))
            let probe = Task { [transport] in await Self.probe(url, transport: transport) }
            probes[kind] = probe
            let isReadable = await probe.value
            probes[kind] = nil
            verdicts[kind] = Verdict(isReadable: isReadable, checkedAt: now())
            return isReadable
        }

        private static func probe(_ url: URL?, transport: any S3PublicHTTPTransport) async -> Bool {
            guard let url else { return false }
            // Any failure to fetch the probe leaves access unproven, so 403s stay errors.
            guard let response = try? await transport.get(url) else { return false }
            try? await ByteStreamSupport.discard(response.body)
            return response.status == 200
        }
    }
#endif
