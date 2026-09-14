import Foundation

final class RedirectingFileManager: FileManager, @unchecked Sendable {
    private let applicationSupportDirectory: URL
    private let homeDirectory: URL?

    init(applicationSupportDirectory: URL, homeDirectory: URL? = nil) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.homeDirectory = homeDirectory
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

    override var homeDirectoryForCurrentUser: URL {
        homeDirectory ?? super.homeDirectoryForCurrentUser
    }
}
