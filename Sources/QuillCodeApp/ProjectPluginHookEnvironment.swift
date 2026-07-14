import Foundation
import QuillCodeCore
import QuillCodePersistence

enum ProjectPluginHookEnvironment {
    static func build(
        base: [String: String] = [:],
        pluginID: String?,
        pluginRootRelativePath: String?,
        workspaceRoot: URL,
        pluginDataBaseDirectory: URL?
    ) throws -> [String: String] {
        var environment = base
        guard let pluginID, let pluginRootRelativePath else { return environment }
        guard let pluginDataBaseDirectory else {
            throw ProjectPluginHookEnvironmentError.pluginDataUnavailable
        }

        let workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let pluginRootCandidate = workspaceRoot
            .appendingPathComponent(pluginRootRelativePath, isDirectory: true)
            .standardizedFileURL
        let values = try pluginRootCandidate.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        let pluginRoot = pluginRootCandidate.resolvingSymlinksInPath()
        guard WorkspaceBoundary.isWithin(pluginRoot, root: workspaceRoot),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            throw ProjectPluginHookEnvironmentError.invalidPluginRoot
        }

        let pluginData = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: pluginDataBaseDirectory,
            workspaceRoot: workspaceRoot,
            pluginID: pluginID
        )
        environment["PLUGIN_ROOT"] = pluginRoot.path
        environment["PLUGIN_DATA"] = pluginData.path
        environment["CLAUDE_PLUGIN_ROOT"] = pluginRoot.path
        environment["CLAUDE_PLUGIN_DATA"] = pluginData.path
        return environment
    }
}

enum ProjectPluginHookEnvironmentError: LocalizedError {
    case invalidPluginRoot
    case pluginDataUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPluginRoot:
            return "Plugin root is missing or outside the current workspace."
        case .pluginDataUnavailable:
            return "Private plugin data storage is unavailable."
        }
    }
}
