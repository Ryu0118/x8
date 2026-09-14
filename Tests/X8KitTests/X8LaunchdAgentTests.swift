import Foundation
import Testing
@testable import X8Kit

@Suite("Launchd LaunchAgent planning")
struct X8LaunchdAgentTests {
    private static func makeAgent(
        profileID: String = "myproject"
    ) -> (agent: X8LaunchdAgent, home: URL, applicationSupport: URL) {
        let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
        let applicationSupport = home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let fileManager = RedirectingFileManager(
            applicationSupportDirectory: applicationSupport,
            homeDirectory: home
        )
        let agent = X8LaunchdAgent(profileID: profileID, fileManager: fileManager)
        return (agent, home, applicationSupport)
    }

    private static func makeInstallPlan(
        agent: X8LaunchdAgent,
        workspaceDirectory: URL? = nil,
        environment: [X8LaunchdAgent.EnvironmentPair] = []
    ) throws -> X8LaunchdAgent.InstallPlan {
        try agent.installPlan(
            executablePath: "/opt/homebrew/bin/x8",
            workingDirectory: URL(filePath: "/Users/tester/src/myproject", directoryHint: .isDirectory),
            workspaceDirectory: workspaceDirectory,
            environment: environment
        )
    }

    @Test
    func socketPathMatchesXcodeServeRunnersDefault() {
        let (agent, _, applicationSupport) = Self.makeAgent(profileID: "myproject")
        let expected = XcodeServeRunner.defaultSocketPath(
            profileID: "myproject",
            fileManager: RedirectingFileManager(applicationSupportDirectory: applicationSupport)
        )
        #expect(agent.socketPath == expected)
    }

    @Test
    func labelIsStableAndProfileScoped() {
        let (agent, _, _) = Self.makeAgent(profileID: "myproject")
        #expect(agent.label == "com.x8.myproject")

        let (other, _, _) = Self.makeAgent(profileID: "otherproject")
        #expect(other.label == "com.x8.otherproject")
    }

    @Test
    func plistURLLivesUnderLaunchAgents() {
        let (agent, home, _) = Self.makeAgent(profileID: "myproject")
        #expect(agent.plistURL == home.appending(path: "Library/LaunchAgents/com.x8.myproject.plist"))
    }

    @Test
    func requiredDirectoriesCoverPlistSocketAndLogs() {
        let (agent, home, applicationSupport) = Self.makeAgent(profileID: "myproject")
        let directories = agent.requiredDirectories
        #expect(directories.contains { $0.path == home.appending(path: "Library/LaunchAgents").path })
        #expect(directories.contains { $0.path == home.appending(path: "Library/Logs/X8").path })
        #expect(directories.contains { $0.path.hasPrefix(applicationSupport.path) })
    }

    @Test
    func serviceTargetUsesGuiDomainAndLabel() {
        let (agent, _, _) = Self.makeAgent(profileID: "myproject")
        #expect(agent.serviceTarget(uid: 501) == "gui/501/com.x8.myproject")
    }

    @Test
    func launchctlArgumentsNeverIncludeTheExecutableName() {
        let (agent, _, _) = Self.makeAgent(profileID: "myproject")
        #expect(agent.bootstrapArguments(uid: 501) == ["bootstrap", "gui/501", agent.plistURL.path])
        #expect(agent.bootoutArguments(uid: 501) == ["bootout", "gui/501/com.x8.myproject"])
        #expect(agent.enableArguments(uid: 501) == ["enable", "gui/501/com.x8.myproject"])
        #expect(agent.printArguments(uid: 501) == ["print", "gui/501/com.x8.myproject"])
    }

    @Test
    func identityNeedsNoInstallOnlyInformation() {
        // uninstall and status only need label/socketPath/serviceTarget/launchctl
        // arguments, none of which an install-specific detail should gate.
        let (agent, _, _) = Self.makeAgent(profileID: "myproject")
        _ = agent.label
        _ = agent.socketPath
        _ = agent.serviceTarget(uid: 501)
        _ = agent.bootoutArguments(uid: 501)
        _ = agent.printArguments(uid: 501)
    }

    @Test
    func plistEncodesTheListenerAtTheDefaultSocketPath() throws {
        let (agent, _, _) = Self.makeAgent(profileID: "myproject")
        let plan = try Self.makeInstallPlan(agent: agent)
        let plist = try PropertyListSerialization.propertyList(
            from: plan.plistData,
            format: nil
        ) as? [String: Any]
        let plistDocument = try #require(plist)

        #expect(plistDocument["Label"] as? String == "com.x8.myproject")
        #expect(plistDocument["WorkingDirectory"] as? String == "/Users/tester/src/myproject")
        #expect(plistDocument["ProcessType"] as? String == "Interactive")

        let sockets = try #require(plistDocument["Sockets"] as? [String: Any])
        let listener = try #require(sockets["Listener"] as? [String: Any])
        #expect(listener["SockPathName"] as? String == agent.socketPath)
        #expect(listener["SockFamily"] as? String == "Unix")
        #expect(listener["SockPathMode"] as? Int == 0o600)
    }

    @Test
    func programArgumentsCarryLaunchdAndSuppressPrintingByDefault() throws {
        let (agent, _, _) = Self.makeAgent(profileID: "myproject")
        let plan = try Self.makeInstallPlan(agent: agent)
        let plist = try PropertyListSerialization.propertyList(
            from: plan.plistData,
            format: nil
        ) as? [String: Any]
        let arguments = try #require(plist?["ProgramArguments"] as? [String])

        #expect(arguments == ["/opt/homebrew/bin/x8", "serve", "--launchd", "--no-print-cache-settings"])
    }

    @Test
    func workspaceDirectoryIsForwardedWhenGiven() throws {
        let (agent, _, _) = Self.makeAgent(profileID: "myproject")
        let workspace = URL(filePath: "/Volumes/Data/workspace", directoryHint: .isDirectory)
        let plan = try Self.makeInstallPlan(agent: agent, workspaceDirectory: workspace)
        let plist = try PropertyListSerialization.propertyList(
            from: plan.plistData,
            format: nil
        ) as? [String: Any]
        let arguments = try #require(plist?["ProgramArguments"] as? [String])

        #expect(arguments.last == "/Volumes/Data/workspace")
        #expect(arguments.contains("--workspace-directory"))
    }

    @Test
    func environmentAlwaysIncludesAMinimalPathEvenWhenCustomPairsAreGiven() throws {
        let (agent, _, _) = Self.makeAgent(profileID: "myproject")
        let plan = try Self.makeInstallPlan(
            agent: agent,
            environment: [.init(key: "AWS_PROFILE", value: "default")]
        )
        let plist = try PropertyListSerialization.propertyList(
            from: plan.plistData,
            format: nil
        ) as? [String: Any]
        let environmentVariables = try #require(plist?["EnvironmentVariables"] as? [String: String])

        #expect(environmentVariables["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(environmentVariables["AWS_PROFILE"] == "default")
    }
}
