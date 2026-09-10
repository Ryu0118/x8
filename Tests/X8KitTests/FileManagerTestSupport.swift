import Foundation

final class RedirectingFileManager: FileManager, @unchecked Sendable {
    private let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        guard directory == .applicationSupportDirectory,
              domainMask.contains(.userDomainMask)
        else {
            return super.urls(for: directory, in: domainMask)
        }
        return [applicationSupportDirectory]
    }
}
