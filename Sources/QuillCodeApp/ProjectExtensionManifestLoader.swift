import Foundation
import QuillCodeCore

public enum ProjectExtensionManifestLoader {
    public static let defaultDirectories: [(relativePath: String, kind: ProjectExtensionKind)] = [
        (".quillcode/plugins", .plugin),
        (".quillcode/skills", .skill),
        (".quillcode/mcp", .mcpServer)
    ]

    public static let defaultMarketplaceDirectories = [
        ".quillcode/marketplace"
    ]

    public static let maxManifests = 48
    public static let maxManifestBytes = 20_000

    public static func load(
        from projectRoot: URL,
        directories: [(relativePath: String, kind: ProjectExtensionKind)] = defaultDirectories,
        maxManifests: Int = maxManifests,
        maxManifestBytes: Int = maxManifestBytes
    ) -> [ProjectExtensionManifest] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let scanDirectories = directories.map(ManifestDirectoryRequest.init)
        let directManifests = loadManifests(
            root: root,
            directories: scanDirectories,
            maxManifests: maxManifests,
            maxManifestBytes: maxManifestBytes
        ) { root, directory, fileURL, maxManifestBytes in
            manifest(
                root: root,
                directory: directory.relativePath,
                kind: directory.kind,
                fileURL: fileURL,
                maxManifestBytes: maxManifestBytes
            )
        }
        return appendingPluginPackages(
            to: directManifests,
            root: root,
            directories: scanDirectories,
            maxManifests: maxManifests,
            maxManifestBytes: maxManifestBytes
        )
    }

    public static func loadMarketplace(
        from projectRoot: URL,
        installedManifests: [ProjectExtensionManifest],
        directories: [String] = defaultMarketplaceDirectories,
        maxManifests: Int = maxManifests,
        maxManifestBytes: Int = maxManifestBytes
    ) -> [ProjectExtensionManifest] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let installedIDs = Set(installedManifests.map(\.id))
        let scanDirectories = directories.map {
            ManifestDirectoryRequest(relativePath: $0, kind: .plugin)
        }
        return loadManifests(
            root: root,
            directories: scanDirectories,
            maxManifests: maxManifests,
            maxManifestBytes: maxManifestBytes,
            excludedIDs: installedIDs
        ) { root, directory, fileURL, maxManifestBytes in
            marketplaceManifest(
                root: root,
                directory: directory.relativePath,
                fileURL: fileURL,
                maxManifestBytes: maxManifestBytes
            )
        }
    }

    private static func loadManifests(
        root: URL,
        directories: [ManifestDirectoryRequest],
        maxManifests: Int,
        maxManifestBytes: Int,
        excludedIDs: Set<String> = [],
        manifestFactory: (URL, ManifestDirectory, URL, Int) -> ProjectExtensionManifest?
    ) -> [ProjectExtensionManifest] {
        var manifests: [ProjectExtensionManifest] = []
        var seenIDs = Set<String>()

        for request in directories {
            guard manifests.count < maxManifests else { break }
            guard let directory = manifestDirectory(
                root: root,
                relativePath: request.relativePath,
                kind: request.kind
            ) else {
                continue
            }

            for fileURL in manifestFiles(in: directory.url) {
                guard manifests.count < maxManifests,
                      let manifest = manifestFactory(root, directory, fileURL, maxManifestBytes),
                      !excludedIDs.contains(manifest.id),
                      seenIDs.insert(manifest.id).inserted
                else {
                    continue
                }
                manifests.append(manifest)
            }
        }

        return manifests
    }

    private static func appendingPluginPackages(
        to directManifests: [ProjectExtensionManifest],
        root: URL,
        directories: [ManifestDirectoryRequest],
        maxManifests: Int,
        maxManifestBytes: Int
    ) -> [ProjectExtensionManifest] {
        guard directManifests.count < maxManifests else { return directManifests }

        var manifests = directManifests
        var seenIDs = Set(manifests.map(\.id))
        var scannedDirectories = Set<String>()
        for directory in directories where directory.kind == .plugin {
            guard manifests.count < maxManifests,
                  scannedDirectories.insert(directory.relativePath).inserted
            else { continue }

            let packages = CodexPluginPackageLoader.load(
                from: root,
                pluginDirectory: directory.relativePath,
                maxPackages: maxManifests - manifests.count,
                maxManifestBytes: maxManifestBytes
            )
            for package in packages where manifests.count < maxManifests {
                // A direct manifest is an explicit project override. If it already claims the
                // plugin ID, do not activate hidden components from the shadowed package.
                guard seenIDs.insert(package.plugin.id).inserted else { continue }
                manifests.append(package.plugin)
                for component in package.components where manifests.count < maxManifests {
                    guard seenIDs.insert(component.id).inserted else { continue }
                    manifests.append(component)
                }
            }
        }
        return manifests
    }

    private static func manifestFiles(in directoryURL: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func manifestDirectory(
        root: URL,
        relativePath: String,
        kind: ProjectExtensionKind
    ) -> ManifestDirectory? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/")
        else {
            return nil
        }

        let components = trimmed
            .split(separator: "/")
            .map(String.init)
        guard components.allSatisfy({ component in
            !component.isEmpty && component != "." && component != ".."
        }) else {
            return nil
        }

        let directoryURL = components
            .reduce(root) { url, component in
                url.appendingPathComponent(component, isDirectory: true)
            }
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard directoryURL.path.hasPrefix(root.path + "/") else {
            return nil
        }

        return ManifestDirectory(
            relativePath: components.joined(separator: "/"),
            kind: kind,
            url: directoryURL
        )
    }

    private static func manifest(
        root: URL,
        directory: String,
        kind: ProjectExtensionKind,
        fileURL: URL,
        maxManifestBytes: Int
    ) -> ProjectExtensionManifest? {
        guard let payload = payload(
            root: root,
            fileURL: fileURL,
            maxManifestBytes: maxManifestBytes
        ) else {
            return nil
        }

        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        return manifest(
            payload: payload,
            kind: kind,
            directory: directory,
            fileURL: resolved
        )
    }

    private static func marketplaceManifest(
        root: URL,
        directory: String,
        fileURL: URL,
        maxManifestBytes: Int
    ) -> ProjectExtensionManifest? {
        guard let payload = payload(
            root: root,
            fileURL: fileURL,
            maxManifestBytes: maxManifestBytes
        ),
              let kind = payload.marketplaceKind
        else {
            return nil
        }

        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        return manifest(
            payload: payload,
            kind: kind,
            directory: directory,
            fileURL: resolved
        )
    }

    private static func payload(
        root: URL,
        fileURL: URL,
        maxManifestBytes: Int
    ) -> ProjectExtensionManifestPayload? {
        guard maxManifestBytes > 0,
              fileURL.pathExtension == "json"
        else {
            return nil
        }

        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? 0) <= maxManifestBytes
        else {
            return nil
        }

        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else {
            return nil
        }

        guard let data = try? Data(contentsOf: resolved),
              data.count <= maxManifestBytes,
              let payload = try? JSONDecoder().decode(ProjectExtensionManifestPayload.self, from: data)
        else {
            return nil
        }

        return payload
    }

    private static func manifest(
        payload: ProjectExtensionManifestPayload,
        kind: ProjectExtensionKind,
        directory: String,
        fileURL: URL
    ) -> ProjectExtensionManifest? {
        let manifestID = payload.normalizedID
        guard !manifestID.isEmpty else {
            return nil
        }

        let relativePath = "\(directory)/\(fileURL.lastPathComponent)"
        let name = payload.displayName
            ?? displayName(from: fileURL.deletingPathExtension().lastPathComponent)
        return ProjectExtensionManifest(
            id: "\(kind.rawValue):\(manifestID)",
            kind: kind,
            name: name,
            summary: payload.summaryText,
            version: payload.versionText,
            sourceURL: payload.sourceText,
            relativePath: relativePath,
            isEnabled: payload.enabled ?? true,
            transport: payload.transportKind(for: kind),
            serverURL: payload.serverURL,
            headers: payload.serverHeaders,
            oauthClientID: payload.oauthClientIDText,
            launchExecutable: payload.launchExecutable,
            launchCommand: payload.launchCommand,
            launchArguments: payload.launchArguments,
            installCommand: payload.installCommandText,
            installTimeoutSeconds: payload.installTimeout,
            updateCommand: payload.updateCommandText,
            updateTimeoutSeconds: payload.updateTimeout
        )
    }

    private static func displayName(from baseName: String) -> String {
        let words = baseName
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard !words.isEmpty else { return baseName }
        return words
            .map { word in
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

private struct ManifestDirectoryRequest {
    var relativePath: String
    var kind: ProjectExtensionKind

    init(relativePath: String, kind: ProjectExtensionKind) {
        self.relativePath = relativePath
        self.kind = kind
    }

    init(_ directory: (relativePath: String, kind: ProjectExtensionKind)) {
        self.relativePath = directory.relativePath
        self.kind = directory.kind
    }
}

private struct ManifestDirectory {
    var relativePath: String
    var kind: ProjectExtensionKind
    var url: URL
}
