import Foundation
import QuillCodeCore

public struct LocalPluginInstallToolExecutor: Sendable {
    public static let maximumFiles = 10_000
    public static let maximumBytes: Int64 = 250 * 1_024 * 1_024
    public static let maximumManifestBytes = 20_000

    public var workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func install(sourceRelativePath: String, expectedPluginName: String) -> ToolResult {
        do {
            let pluginID = try Self.normalizedPluginID(expectedPluginName)
            let source = try sourceDirectory(sourceRelativePath)
            try validatePackage(at: source, expectedPluginID: pluginID)
            try validateTree(at: source)

            let pluginsDirectory = try pluginsDirectoryURL()
            let destination = pluginsDirectory.appendingPathComponent(pluginID, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw InstallError.alreadyInstalled(pluginID)
            }

            try FileManager.default.createDirectory(
                at: pluginsDirectory,
                withIntermediateDirectories: true
            )
            let staging = pluginsDirectory.appendingPathComponent(
                ".\(pluginID).install-\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: staging) }

            try FileManager.default.copyItem(at: source, to: staging)
            try validatePackage(at: staging, expectedPluginID: pluginID)
            try validateTree(at: staging)
            try FileManager.default.moveItem(at: staging, to: destination)

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

    private func validatePackage(at root: URL, expectedPluginID: String) throws {
        guard let manifest = WorkspaceBoundary.safeURL(".codex-plugin/plugin.json", root: root) else {
            throw InstallError.invalidManifest
        }
        let values = try manifest.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= Self.maximumManifestBytes,
              let data = try? Data(contentsOf: manifest),
              data.count <= Self.maximumManifestBytes,
              let identity = try? JSONDecoder().decode(PluginIdentity.self, from: data),
              try Self.normalizedPluginID(identity.name) == expectedPluginID
        else {
            throw InstallError.invalidManifest
        }
    }

    private func validateTree(at root: URL) throws {
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: [],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw InstallError.unreadablePackage
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true
            else {
                throw InstallError.unsupportedEntry(url.lastPathComponent)
            }
            fileCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
            guard fileCount <= Self.maximumFiles, totalBytes <= Self.maximumBytes else {
                throw InstallError.packageTooLarge
            }
        }
        guard !enumerationFailed else {
            throw InstallError.unreadablePackage
        }
    }

    private static func isExplicitLocalPath(_ value: String) -> Bool {
        value.hasPrefix("./") && value.count > 2 && !value.contains("\0")
    }

    private static func normalizedPluginID(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty,
              trimmed.count <= 128,
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" })
        else {
            throw InstallError.invalidPluginName
        }
        return trimmed
    }
}

private struct PluginIdentity: Decodable {
    var name: String
}

private enum InstallError: Error, CustomStringConvertible {
    case alreadyInstalled(String)
    case invalidDestination
    case invalidManifest
    case invalidPluginName
    case invalidSourcePath
    case packageTooLarge
    case unreadablePackage
    case unsupportedEntry(String)

    var description: String {
        switch self {
        case .alreadyInstalled(let name):
            return "Plugin \(name) is already installed."
        case .invalidDestination:
            return "The plugin destination is outside the project workspace."
        case .invalidManifest:
            return "The plugin manifest is missing, invalid, or no longer matches the marketplace entry."
        case .invalidPluginName:
            return "The marketplace plugin name is invalid."
        case .invalidSourcePath:
            return "The local plugin source must be an existing ./ path inside the project workspace."
        case .packageTooLarge:
            return "The local plugin package is too large to install."
        case .unreadablePackage:
            return "The local plugin package could not be read."
        case .unsupportedEntry(let name):
            return "The local plugin package contains an unsupported or symbolic entry: \(name)."
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
