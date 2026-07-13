import Foundation
import QuillCodeCore

public struct QuillCodePaths: Sendable, Hashable {
    public var home: URL
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
    public var subagentSessionsDirectory: URL { home.appendingPathComponent("subagent-sessions") }

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".quillcode")) {
        self.home = home
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
    }
}
