import Foundation
import QuillCodeCore

public enum ProjectExtensionManifestLoader {
    public static let defaultDirectories: [(relativePath: String, kind: ProjectExtensionKind)] = [
        (".quillcode/plugins", .plugin),
        (".quillcode/skills", .skill),
        (".quillcode/mcp", .mcpServer)
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
        var manifests: [ProjectExtensionManifest] = []
        var seenIDs = Set<String>()

        for directory in directories {
            guard manifests.count < maxManifests else {
                break
            }

            guard let directory = manifestDirectory(
                root: root,
                relativePath: directory.relativePath,
                kind: directory.kind
            ) else {
                continue
            }

            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory.url,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for fileURL in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard manifests.count < maxManifests,
                      let manifest = manifest(
                        root: root,
                        directory: directory.relativePath,
                        kind: directory.kind,
                        fileURL: fileURL,
                        maxManifestBytes: maxManifestBytes
                      ),
                      !seenIDs.contains(manifest.id)
                else {
                    continue
                }
                seenIDs.insert(manifest.id)
                manifests.append(manifest)
            }
        }

        return manifests
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
              let payload = try? JSONDecoder().decode(ManifestPayload.self, from: data)
        else {
            return nil
        }

        let manifestID = payload.normalizedID
        guard !manifestID.isEmpty else {
            return nil
        }

        let relativePath = "\(directory)/\(resolved.lastPathComponent)"
        let name = payload.displayName
            ?? displayName(from: resolved.deletingPathExtension().lastPathComponent)
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

private struct ManifestDirectory {
    var relativePath: String
    var kind: ProjectExtensionKind
    var url: URL
}

private struct ManifestPayload: Decodable {
    var id: String?
    var name: String?
    var description: String?
    var summary: String?
    var version: String?
    var source: String?
    var homepage: String?
    var enabled: Bool?
    var command: String?
    var args: [String]?
    var transport: String?
    var installCommand: String?
    var installTimeoutSeconds: Int?
    var updateCommand: String?
    var updateTimeoutSeconds: Int?

    var normalizedID: String {
        (id ?? name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    var displayName: String? {
        normalizedOptional(name, maxLength: 120)
    }

    var summaryText: String {
        let text = summary ?? description ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var versionText: String? {
        normalizedOptional(version, maxLength: 80)
    }

    var sourceText: String? {
        normalizedOptional(source ?? homepage, maxLength: 500)
    }

    var updateCommandText: String? {
        normalizedOptional(updateCommand, maxLength: 1_200)
    }

    var installCommandText: String? {
        normalizedOptional(installCommand, maxLength: 1_200)
    }

    var updateTimeout: Int? {
        boundedTimeout(updateTimeoutSeconds)
    }

    var installTimeout: Int? {
        boundedTimeout(installTimeoutSeconds)
    }

    var launchCommand: String? {
        guard let command = launchExecutable
        else {
            return nil
        }
        let args = (args ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !args.isEmpty else {
            return command
        }
        return ([command] + args).joined(separator: " ")
    }

    var launchExecutable: String? {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty
        else {
            return nil
        }
        return command
    }

    var launchArguments: [String]? {
        let args = (args ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return args.isEmpty ? nil : args
    }

    func transportKind(for kind: ProjectExtensionKind) -> ProjectExtensionTransport? {
        if let transport = transport?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           let parsed = ProjectExtensionTransport(rawValue: transport) {
            return parsed
        }
        return kind == .mcpServer && launchCommand != nil ? .stdio : nil
    }

    private func boundedTimeout(_ seconds: Int?) -> Int? {
        guard let seconds else { return nil }
        return min(max(seconds, 5), 1_800)
    }

    private func normalizedOptional(_ value: String?, maxLength: Int) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return nil
        }
        guard text.count <= maxLength else {
            return nil
        }
        return text
    }
}
