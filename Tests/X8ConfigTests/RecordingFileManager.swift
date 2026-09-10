import Foundation

final class RecordingFileManager: FileManager, @unchecked Sendable {
    private let recorder = PathRecorder()

    var fileExistsPaths: [String] {
        recorder.paths
    }

    override func fileExists(atPath path: String) -> Bool {
        recorder.append(path)
        return super.fileExists(atPath: path)
    }
}

private final class PathRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedPaths: [String] = []

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }

    func append(_ path: String) {
        lock.lock()
        recordedPaths.append(path)
        lock.unlock()
    }
}
