import Foundation
import Testing
@testable import X8Kit

@Suite("X8 cache metrics aggregation")
struct X8CacheMetricsTests {
    @Test("aggregates outcomes, transfer bytes, and latency percentiles")
    func aggregatesEvents() async {
        let metrics = X8CacheMetricsStore()
        await metrics.record(
            X8CacheMetricsEvent(
                operation: .get,
                outcome: .hit,
                byteCount: 12,
                latency: .milliseconds(10)
            )
        )
        await metrics.record(
            X8CacheMetricsEvent(
                operation: .get,
                outcome: .miss,
                latency: .milliseconds(30)
            )
        )
        await metrics.record(
            X8CacheMetricsEvent(
                operation: .put,
                outcome: .stored,
                byteCount: 7,
                latency: .milliseconds(20)
            )
        )
        await metrics.record(
            X8CacheMetricsEvent(
                operation: .put,
                outcome: .remoteError,
                latency: .milliseconds(40)
            )
        )

        let snapshot = await metrics.snapshot()

        #expect(snapshot.getRequests == 2)
        #expect(snapshot.putRequests == 2)
        #expect(snapshot.cacheHits == 1)
        #expect(snapshot.cacheMisses == 1)
        #expect(snapshot.remoteErrors == 1)
        #expect(snapshot.bytesDownloaded == 12)
        #expect(snapshot.bytesUploaded == 7)
        #expect(snapshot.getLatencyP50Milliseconds == 10)
        #expect(snapshot.getLatencyP95Milliseconds == 30)
        #expect(snapshot.putLatencyP50Milliseconds == 20)
        #expect(snapshot.putLatencyP95Milliseconds == 40)
    }

    @Test("renders every required metric with stable names")
    func rendersSnapshot() {
        let snapshot = X8CacheMetricsSnapshot(
            getRequests: 1,
            putRequests: 2,
            cacheHits: 3,
            cacheMisses: 4,
            remoteErrors: 5,
            corruptedObjects: 6,
            bytesDownloaded: 7,
            bytesUploaded: 8,
            getLatencyP50Milliseconds: 1.25,
            getLatencyP95Milliseconds: nil,
            putLatencyP50Milliseconds: 2.5,
            putLatencyP95Milliseconds: 5
        )

        let output = X8CacheMetricsPresentation.render(snapshot)

        #expect(output.contains("get_requests=1"))
        #expect(output.contains("corrupted_objects=6"))
        #expect(output.contains("get_latency_p50=1.250ms"))
        #expect(output.contains("get_latency_p95=-"))
    }

    @Test("round trips a snapshot through the filesystem boundary")
    func persistsSnapshot() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "x8-metrics-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = X8CacheMetricsSnapshot(
            getRequests: 1,
            putRequests: 2,
            cacheHits: 3,
            cacheMisses: 4,
            remoteErrors: 5,
            corruptedObjects: 6,
            bytesDownloaded: 7,
            bytesUploaded: 8,
            getLatencyP50Milliseconds: 1,
            getLatencyP95Milliseconds: 2,
            putLatencyP50Milliseconds: 3,
            putLatencyP95Milliseconds: 4
        )

        let file = X8CacheMetricsSnapshotFile()
        try await file.write(snapshot, to: url)

        #expect(try await file.read(from: url) == snapshot)
    }

    @Test("reports an invalid persisted snapshot")
    func rejectsMalformedSnapshot() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "x8-metrics-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not-json".utf8).write(to: url)

        await #expect(throws: DecodingError.self) {
            _ = try await X8CacheMetricsSnapshotFile().read(from: url)
        }
    }

    @Test("loads the persisted snapshot for a serve profile")
    func loadsProfileSnapshot() async throws {
        let profileID = "x8-stats-" + UUID().uuidString
        let root = FileManager.default.temporaryDirectory
            .appending(path: "x8-stats-" + UUID().uuidString)
        let fileManager = RedirectingFileManager(applicationSupportDirectory: root)
        let metricsURL = XcodeServeRunner.defaultMetricsFileURL(
            profileID: profileID,
            fileManager: fileManager
        )
        let directory = metricsURL.deletingLastPathComponent()
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let snapshot = X8CacheMetricsSnapshot(
            getRequests: 1,
            putRequests: 0,
            cacheHits: 1,
            cacheMisses: 0,
            remoteErrors: 0,
            corruptedObjects: 0,
            bytesDownloaded: 8,
            bytesUploaded: 0,
            getLatencyP50Milliseconds: 1,
            getLatencyP95Milliseconds: 1,
            putLatencyP50Milliseconds: nil,
            putLatencyP95Milliseconds: nil
        )
        try await X8CacheMetricsSnapshotFile(fileManager: fileManager).write(
            snapshot,
            to: metricsURL
        )

        #expect(
            try await X8CacheStatsRunner(fileManager: fileManager).load(profileID: profileID)
                == snapshot
        )
    }
}
