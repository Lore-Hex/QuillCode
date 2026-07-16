import Foundation
import QuillCodeCore

public struct LocalPluginInstallToolExecutor: Sendable {
    public static let maximumFiles = BoundedPluginPackageInstaller.maximumFiles
    public static let maximumBytes = BoundedPluginPackageInstaller.maximumBytes
    public static let maximumManifestBytes = BoundedPluginPackageInstaller.maximumManifestBytes

    public var workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func install(sourceRelativePath: String, expectedPluginName: String) -> ToolResult {
        do {
            let pluginID = try BoundedPluginPackageInstaller.normalizedIdentifier(expectedPluginName)
            let source = try sourceDirectory(sourceRelativePath)
            let pluginsDirectory = try pluginsDirectoryURL()
            let destination = pluginsDirectory.appendingPathComponent(pluginID, isDirectory: true)
            try BoundedPluginPackageInstaller.install(
                source: source,
                expectedPluginName: pluginID,
                destination: destination,
                destinationRoot: pluginsDirectory
            )

            return ToolResult(
                ok: true,
                stdout: "Installed plugin \(expectedPluginName) at .quillcode/plugins/\(pluginID)\n",
                artifacts: [destination.path]
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func sourceDirectory(_ relativePath: String) throws -> URL {
        guard Self.isExplicitLocalPath(relativePath),
              let source = WorkspaceBoundary.safeURL(relativePath, root: workspaceRoot)
        else {
            throw InstallError.invalidSourcePath
        }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw InstallError.invalidSourcePath
        }
        return source
    }

    private func pluginsDirectoryURL() throws -> URL {
        guard let directory = WorkspaceBoundary.safeURL(".quillcode/plugins", root: workspaceRoot) else {
            throw InstallError.invalidDestination
        }
        return directory
    }

    private static func isExplicitLocalPath(_ value: String) -> Bool {
        value.hasPrefix("./") && value.count > 2 && !value.contains("\0")
    }

}
private enum InstallError: Error, CustomStringConvertible {
    case invalidDestination
    case invalidSourcePath

    var description: String {
        switch self {
        case .invalidDestination:
            return "The plugin destination is outside the project workspace."
        case .invalidSourcePath:
            return "The local plugin source must be an existing ./ path inside the project workspace."
        }
    }
}

public extension ToolDefinition {
    static let localPluginInstall = ToolDefinition(
        name: "host.plugin.install_local",
        description: "Install a reviewed local plugin package from this project.",
        parametersJSON: #"{"type":"object","properties":{"source":{"type":"string"},"pluginName":{"type":"string"}},"required":["source","pluginName"],"additionalProperties":false}"#,
        host: .plugin,
        risk: .append
    )
}
