import Foundation
import QuillCodeCore

public struct QuillCodePaths: Sendable, Hashable {
    public var home: URL
    public var configFile: URL { home.appendingPathComponent("config.toml") }
    public var automationsFile: URL { home.appendingPathComponent("automations.json") }
    public var projectsFile: URL { home.appendingPathComponent("projects.json") }
    public var sidebarSavedSearchesFile: URL { home.appendingPathComponent("sidebar-saved-searches.json") }
    public var threadsDirectory: URL { home.appendingPathComponent("threads") }
    public var attachmentsDirectory: URL { home.appendingPathComponent("attachments") }
    public var memoriesDirectory: URL { home.appendingPathComponent("memories") }
    public var worktreeSnapshotsDirectory: URL { home.appendingPathComponent("worktree-snapshots") }
    public var managedWorktreesDirectory: URL { home.appendingPathComponent("worktrees") }
    public var secretsDirectory: URL { home.appendingPathComponent("secrets") }
    public var permissionsDirectory: URL { home.appendingPathComponent("permissions") }

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".quillcode")) {
        self.home = home
    }

    public func ensure() throws {
        for directory in [
            home,
            threadsDirectory,
            attachmentsDirectory,
            memoriesDirectory,
            worktreeSnapshotsDirectory,
            managedWorktreesDirectory,
            secretsDirectory,
            permissionsDirectory
        ] {
            try Self.ensurePrivateDirectory(directory)
        }
    }

    private static func ensurePrivateDirectory(_ directory: URL) throws {
        let permissions = NSNumber(value: Int16(0o700))
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: permissions]
        )
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory.path)
    }
}
