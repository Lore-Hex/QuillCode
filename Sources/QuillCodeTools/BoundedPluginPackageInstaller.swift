import Foundation
import QuillCodeCore

/// Copies a data-only plugin package through a bounded staging directory.
///
/// Package discovery and installation deliberately never execute lifecycle scripts. Both the
/// source and staged copy are validated so a package cannot swap its manifest or introduce a
/// symbolic entry between discovery and activation.
public enum BoundedPluginPackageInstaller {
    public static let maximumFiles = 10_000
    public static let maximumBytes: Int64 = 250 * 1_024 * 1_024
    public static let maximumManifestBytes = 20_000

    private static let manifestRelativePaths = [
        ".codex-plugin/plugin.json",
        ".claude-plugin/plugin.json"
    ]

    @discardableResult
    public static func install(
        source: URL,
        expectedPluginName: String,
        destination: URL,
        destinationRoot: URL,
        replaceExisting: Bool = false
    ) throws -> URL {
        let pluginID = try normalizedIdentifier(expectedPluginName)
        let source = try validatedSourceDirectory(source)
        try validatePackage(at: source, expectedPluginID: pluginID)
        try validateTree(at: source)

        let destinationRoot = try validatedDestinationRoot(destinationRoot)
        let destination = destination.standardizedFileURL
        guard WorkspaceBoundary.isWithin(destination, root: destinationRoot),
              destination.deletingLastPathComponent().path == destinationRoot.path,
              destination.lastPathComponent == pluginID
        else {
            throw PluginPackageInstallError.invalidDestination
        }

        let fileManager = FileManager.default
        let staging = destinationRoot.appendingPathComponent(
            ".\(pluginID).install-\(UUID().uuidString)",
            isDirectory: true
        )
        let backup = destinationRoot.appendingPathComponent(
            ".\(pluginID).replace-\(UUID().uuidString)",
            isDirectory: true
        )
        var movedExistingPackage = false
        defer {
            try? fileManager.removeItem(at: staging)
        }

        try fileManager.copyItem(at: source, to: staging)
        try validatePackage(at: staging, expectedPluginID: pluginID)
        try validateTree(at: staging)

        if fileManager.fileExists(atPath: destination.path) {
            guard replaceExisting else {
                throw PluginPackageInstallError.alreadyInstalled(pluginID)
            }
            try validateReplaceableDestination(destination, root: destinationRoot)
            try fileManager.moveItem(at: destination, to: backup)
            movedExistingPackage = true
        }

        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if movedExistingPackage,
               !fileManager.fileExists(atPath: destination.path),
               fileManager.fileExists(atPath: backup.path) {
                do {
                    try fileManager.moveItem(at: backup, to: destination)
                } catch let recoveryError {
                    throw PluginPackageInstallError.replacementRecoveryFailed(
                        backup: backup.path,
                        reason: recoveryError.localizedDescription
                    )
                }
            }
            throw error
        }
        if movedExistingPackage {
            try? fileManager.removeItem(at: backup)
        }
        return destination
    }

    public static func normalizedIdentifier(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !result.isEmpty,
              result.count <= 128,
              result.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
              })
        else {
            throw PluginPackageInstallError.invalidPluginName
        }
        return result
    }

    public static func validatePackage(at root: URL, expectedPluginID: String) throws {
        for relativePath in manifestRelativePaths {
            guard let manifest = WorkspaceBoundary.safeURL(relativePath, root: root) else { continue }
            let values = try? manifest.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  (values?.fileSize ?? Self.maximumManifestBytes + 1) <= Self.maximumManifestBytes,
                  let data = try? Data(contentsOf: manifest, options: [.mappedIfSafe]),
                  data.count <= Self.maximumManifestBytes,
                  let identity = try? JSONDecoder().decode(PluginPackageIdentity.self, from: data),
                  let name = try? normalizedIdentifier(identity.name)
            else { continue }
            guard name == expectedPluginID else {
                throw PluginPackageInstallError.invalidManifest
            }
            return
        }
        throw PluginPackageInstallError.invalidManifest
    }

    public static func validateTree(at root: URL) throws {
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
            throw PluginPackageInstallError.unreadablePackage
        }

        var entryCount = 0
        var totalBytes: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true
            else {
                throw PluginPackageInstallError.unsupportedEntry(url.lastPathComponent)
            }
            entryCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
            guard entryCount <= maximumFiles, totalBytes <= maximumBytes else {
                throw PluginPackageInstallError.packageTooLarge
            }
        }
        guard !enumerationFailed else {
            throw PluginPackageInstallError.unreadablePackage
        }
    }

    private static func validatedSourceDirectory(_ source: URL) throws -> URL {
        let requested = source.standardizedFileURL
        let values = try? requested.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let resolved = requested.resolvingSymlinksInPath()
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true,
              resolved.path == requested.path
        else {
            throw PluginPackageInstallError.invalidSourcePath
        }
        return requested
    }

    private static func validatedDestinationRoot(_ root: URL) throws -> URL {
        let requested = root.standardizedFileURL
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
        let values = try? requested.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let resolved = requested.resolvingSymlinksInPath()
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true,
              resolved.path == requested.path
        else {
            throw PluginPackageInstallError.invalidDestination
        }
        return requested
    }

    private static func validateReplaceableDestination(_ destination: URL, root: URL) throws {
        let values = try? destination.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true,
              destination.resolvingSymlinksInPath().path == destination.path,
              WorkspaceBoundary.isWithin(destination, root: root)
        else {
            throw PluginPackageInstallError.invalidDestination
        }
    }
}

public enum PluginPackageInstallError: Error, CustomStringConvertible, Equatable {
    case alreadyInstalled(String)
    case invalidDestination
    case invalidManifest
    case invalidPluginName
    case invalidSourcePath
    case packageTooLarge
    case replacementRecoveryFailed(backup: String, reason: String)
    case unreadablePackage
    case unsupportedEntry(String)

    public var description: String {
        switch self {
        case .alreadyInstalled(let name):
            "Plugin \(name) is already installed."
        case .invalidDestination:
            "The plugin destination is invalid or crosses a symbolic path."
        case .invalidManifest:
            "The plugin manifest is missing, invalid, or no longer matches the marketplace entry."
        case .invalidPluginName:
            "The marketplace plugin name is invalid."
        case .invalidSourcePath:
            "The local plugin source must be a real directory without symbolic path components."
        case .packageTooLarge:
            "The local plugin package is too large to install."
        case .replacementRecoveryFailed(let backup, let reason):
            "The previous plugin could not be restored from \(backup): \(reason)"
        case .unreadablePackage:
            "The local plugin package could not be read."
        case .unsupportedEntry(let name):
            "The local plugin package contains an unsupported or symbolic entry: \(name)."
        }
    }
}

private struct PluginPackageIdentity: Decodable {
    var name: String
}
