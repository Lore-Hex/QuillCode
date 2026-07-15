import Foundation
import QuillCodeCore

public struct HookConfigurationPaths: Sendable, Hashable {
    public var userQuillCodeDirectory: URL?
    public var userCodexDirectory: URL?
    public var systemQuillCodeDirectory: URL?
    public var systemCodexDirectory: URL?
    /// Ordered from lower to higher policy precedence.
    public var managedRequirementFiles: [URL]

    public init(
        userQuillCodeDirectory: URL? = nil,
        userCodexDirectory: URL? = nil,
        systemQuillCodeDirectory: URL? = nil,
        systemCodexDirectory: URL? = nil,
        managedRequirementFiles: [URL] = []
    ) {
        self.userQuillCodeDirectory = userQuillCodeDirectory
        self.userCodexDirectory = userCodexDirectory
        self.systemQuillCodeDirectory = systemQuillCodeDirectory
        self.systemCodexDirectory = systemCodexDirectory
        self.managedRequirementFiles = managedRequirementFiles
    }

    public static func isolated(home: URL) -> HookConfigurationPaths {
        HookConfigurationPaths(userQuillCodeDirectory: home)
    }

    public static func live(
        quillCodeHome: URL,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HookConfigurationPaths {
        HookConfigurationPaths(
            userQuillCodeDirectory: quillCodeHome,
            userCodexDirectory: userHome.appendingPathComponent(".codex", isDirectory: true),
            systemQuillCodeDirectory: URL(fileURLWithPath: "/etc/quillcode", isDirectory: true),
            systemCodexDirectory: URL(fileURLWithPath: "/etc/codex", isDirectory: true),
            managedRequirementFiles: [
                URL(fileURLWithPath: "/etc/codex/requirements.toml"),
                URL(fileURLWithPath: "/etc/quillcode/requirements.toml")
            ]
        )
    }
}

public struct QuillCodePaths: Sendable, Hashable {
    public var home: URL
    public var hookConfigurationPaths: HookConfigurationPaths
    public var configFile: URL { home.appendingPathComponent("config.toml") }
    public var automationsFile: URL { home.appendingPathComponent("automations.json") }
    public var projectsFile: URL { home.appendingPathComponent("projects.json") }
    public var sidebarSavedSearchesFile: URL { home.appendingPathComponent("sidebar-saved-searches.json") }
    public var threadsDirectory: URL { home.appendingPathComponent("threads") }
    public var subagentThreadsDirectory: URL { home.appendingPathComponent("subagent-threads") }
    public var subagentApprovalPayloadsDirectory: URL { home.appendingPathComponent("subagent-approval-payloads") }
    public var attachmentsDirectory: URL { home.appendingPathComponent("attachments") }
    public var memoriesDirectory: URL { home.appendingPathComponent("memories") }
    public var worktreeSnapshotsDirectory: URL { home.appendingPathComponent("worktree-snapshots") }
    public var worktreesDirectory: URL { home.appendingPathComponent("worktrees") }
    public var secretsDirectory: URL { home.appendingPathComponent("secrets") }
    public var permissionsDirectory: URL { home.appendingPathComponent("permissions") }
    public var hookTrustDirectory: URL { home.appendingPathComponent("hook-trust") }
    public var pluginDataDirectory: URL { home.appendingPathComponent("plugin-data") }
    public var subagentSessionsDirectory: URL { home.appendingPathComponent("subagent-sessions") }
    public var importsDirectory: URL { home.appendingPathComponent("imports") }
    public var agentImportReceiptFile: URL { importsDirectory.appendingPathComponent("receipts.json") }

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quillcode", isDirectory: true)
        self.home = home
        self.hookConfigurationPaths = .live(quillCodeHome: home)
    }

    /// Explicit homes are isolated by default so tests and portable installations never read the
    /// host user's Codex or system configuration accidentally.
    public init(home: URL, hookConfigurationPaths: HookConfigurationPaths? = nil) {
        self.home = home
        self.hookConfigurationPaths = hookConfigurationPaths ?? .isolated(home: home)
    }

    public func ensure() throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: threadsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subagentThreadsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: subagentApprovalPayloadsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: subagentApprovalPayloadsDirectory.path
        )
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: memoriesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeSnapshotsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secretsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subagentSessionsDirectory, withIntermediateDirectories: true)
        try PrivateDirectory.ensureExists(at: pluginDataDirectory)
        try PrivateDirectory.ensureExists(at: importsDirectory)
    }
}
