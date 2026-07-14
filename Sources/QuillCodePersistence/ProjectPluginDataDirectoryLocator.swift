import Foundation
import QuillCodeCore

public enum ProjectPluginDataDirectoryLocator {
    public static func directoryURL(
        baseDirectory: URL,
        workspaceRoot: URL,
        pluginID: String
    ) throws -> URL {
        let canonicalWorkspace = WorkspaceBoundary.symlinkResolvedPath(workspaceRoot.standardizedFileURL)
        let workspaceName = WorkspaceScopedStoreFileLocator.sanitizedComponent(
            workspaceRoot.lastPathComponent,
            fallback: "project",
            maxLength: 48
        )
        let pluginName = WorkspaceScopedStoreFileLocator.sanitizedComponent(
            pluginID,
            fallback: "plugin",
            maxLength: 48
        )
        let workspaceDirectory = baseDirectory.appendingPathComponent(
            "\(workspaceName)-\(WorkspaceScopedStoreFileLocator.fnv1a64Hex(canonicalWorkspace))",
            isDirectory: true
        )
        let pluginDirectory = workspaceDirectory.appendingPathComponent(
            "\(pluginName)-\(WorkspaceScopedStoreFileLocator.fnv1a64Hex(pluginID))",
            isDirectory: true
        )

        try PrivateDirectory.ensureExists(at: baseDirectory)
        try PrivateDirectory.ensureExists(at: workspaceDirectory)
        try PrivateDirectory.ensureExists(at: pluginDirectory)
        return pluginDirectory.standardizedFileURL
    }
}
