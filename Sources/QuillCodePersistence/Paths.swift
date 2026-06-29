import Foundation
import QuillCodeCore

public struct QuillCodePaths: Sendable, Hashable {
    public var home: URL
    public var configFile: URL { home.appendingPathComponent("config.toml") }
    public var automationsFile: URL { home.appendingPathComponent("automations.json") }
    public var projectsFile: URL { home.appendingPathComponent("projects.json") }
    public var sidebarSavedSearchesFile: URL { home.appendingPathComponent("sidebar-saved-searches.json") }
    public var threadsDirectory: URL { home.appendingPathComponent("threads") }
    public var memoriesDirectory: URL { home.appendingPathComponent("memories") }
    public var secretsDirectory: URL { home.appendingPathComponent("secrets") }

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".quillcode")) {
        self.home = home
    }

    public func ensure() throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: threadsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: memoriesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secretsDirectory, withIntermediateDirectories: true)
    }
}
